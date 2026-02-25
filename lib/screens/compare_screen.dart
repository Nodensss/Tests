import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/question.dart';
import '../state/app_state.dart';

class CompareScreen extends StatelessWidget {
  const CompareScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final stats = appState.uploadDatabaseStats;
    final similar = appState.uploadSimilarQuestions;
    final mismatches = appState.uploadAnswerMismatchQuestions;
    final pureNew = appState.uploadNewQuestions;
    final quality = appState.dbQualityReport;

    return SelectionArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
        children: <Widget>[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Text(
                    'Сравнение импорта с базой',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Порог похожести по тексту вопроса: 60%. В разделе "Конфликт ответа" показаны похожие вопросы с другим правильным ответом.',
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: <Widget>[
                      FilledButton.tonalIcon(
                        onPressed:
                            appState.busy || appState.uploadQuestions.isEmpty
                            ? null
                            : appState.analyzeUploadAgainstDatabase,
                        icon: const Icon(Icons.sync),
                        label: const Text('Пересчитать сравнение'),
                      ),
                      if (appState.uploadQuestions.isNotEmpty)
                        Chip(
                          label: Text(
                            'В загрузке: ${appState.uploadQuestions.length}',
                          ),
                        ),
                      FilledButton.tonalIcon(
                        onPressed: appState.busy
                            ? null
                            : appState.analyzeDatabaseQuality,
                        icon: const Icon(Icons.health_and_safety_outlined),
                        label: const Text('Анализ качества БД'),
                      ),
                    ],
                  ),
                  if (appState.uploadQuestions.isEmpty) ...<Widget>[
                    const SizedBox(height: 8),
                    const Text(
                      'Сначала загрузите и разберите Excel на вкладке Upload.',
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (stats != null) ...<Widget>[
            const SizedBox(height: 8),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: <Widget>[
                    _MetricItem(
                      title: 'Уникальных в загрузке',
                      value: '${stats.uniqueRows}',
                    ),
                    _MetricItem(
                      title: 'Точные совпадения',
                      value: '${stats.alreadyInDatabase}',
                    ),
                    _MetricItem(
                      title: 'Похожие (>=60%)',
                      value: '${stats.similarByQuestionText}',
                    ),
                    _MetricItem(
                      title: 'Конфликт ответа',
                      value: '${stats.answerMismatches}',
                    ),
                    _MetricItem(
                      title: 'Чисто новые',
                      value: '${stats.pureNew}',
                    ),
                    _MetricItem(
                      title: 'Новых/обновляемых в БД',
                      value: '${stats.newForDatabase}',
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            _MatchesSection(
              title: 'Похожие вопросы (ответ совпадает)',
              subtitle:
                  'Похожесть по тексту >= 60%, правильный ответ одинаковый.',
              matches: similar,
            ),
            const SizedBox(height: 8),
            _MatchesSection(
              title: 'Конфликт по ответу',
              subtitle:
                  'Похожесть по тексту >= 60%, но правильный ответ отличается.',
              matches: mismatches,
              emphasizeConflict: true,
            ),
            const SizedBox(height: 8),
            _PureNewSection(questions: pureNew),
          ],
          if (quality != null) ...<Widget>[
            const SizedBox(height: 8),
            _DatabaseQualitySection(report: quality),
          ],
        ],
      ),
    );
  }
}

class _MetricItem extends StatelessWidget {
  const _MetricItem({required this.title, required this.value});

  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 190,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: Colors.white.withValues(alpha: 0.04),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            title,
            style: TextStyle(color: Colors.grey.shade300, fontSize: 12),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 20),
          ),
        ],
      ),
    );
  }
}

class _MatchesSection extends StatelessWidget {
  const _MatchesSection({
    required this.title,
    required this.subtitle,
    required this.matches,
    this.emphasizeConflict = false,
  });

  final String title;
  final String subtitle;
  final List<UploadSimilarityMatch> matches;
  final bool emphasizeConflict;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              '$title (${matches.length})',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(subtitle, style: TextStyle(color: Colors.grey.shade300)),
            const SizedBox(height: 10),
            if (matches.isEmpty)
              const Text('Нет записей')
            else
              ...matches.take(200).map((match) {
                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.white24),
                    color: emphasizeConflict
                        ? Colors.red.withValues(alpha: 0.09)
                        : Colors.blueGrey.withValues(alpha: 0.12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        'Похожесть: ${(match.similarity * 100).toStringAsFixed(1)}%',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 4),
                      const Text('Новый импорт:'),
                      SelectableText(match.incoming.questionText),
                      const SizedBox(height: 4),
                      Text(
                        'Ответ (новый): ${match.incoming.correctAnswer}',
                        style: TextStyle(
                          color: emphasizeConflict
                              ? Colors.redAccent
                              : Colors.greenAccent,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text('Уже в базе:'),
                      SelectableText(match.existing.questionText),
                      const SizedBox(height: 4),
                      Text(
                        'Ответ (в базе): ${match.existing.correctAnswer}',
                        style: TextStyle(
                          color: emphasizeConflict
                              ? Colors.greenAccent
                              : Colors.greenAccent,
                        ),
                      ),
                      if ((match.incoming.sourceFile ?? '').trim().isNotEmpty)
                        Text(
                          'Источник импорта: ${match.incoming.sourceFile}',
                          style: TextStyle(color: Colors.grey.shade400),
                        ),
                      if ((match.existing.sourceFile ?? '').trim().isNotEmpty)
                        Text(
                          'Источник в БД: ${match.existing.sourceFile}',
                          style: TextStyle(color: Colors.grey.shade400),
                        ),
                    ],
                  ),
                );
              }),
            if (matches.length > 200)
              Text(
                'Показаны первые 200 из ${matches.length}.',
                style: TextStyle(color: Colors.grey.shade400),
              ),
          ],
        ),
      ),
    );
  }
}

class _DatabaseQualitySection extends StatefulWidget {
  const _DatabaseQualitySection({required this.report});

  final DbQualityReport report;

  @override
  State<_DatabaseQualitySection> createState() =>
      _DatabaseQualitySectionState();
}

class _DatabaseQualitySectionState extends State<_DatabaseQualitySection> {
  final GlobalKey _issuesKey = GlobalKey();
  String? _selectedCategory;

  List<DbQualityIssue> _filteredIssues() {
    if (_selectedCategory == null || _selectedCategory!.trim().isEmpty) {
      return widget.report.issues;
    }
    return widget.report.issues
        .where((issue) => issue.category == _selectedCategory)
        .toList(growable: false);
  }

  void _selectCategory(String? category) {
    setState(() {
      if (category == null || category.trim().isEmpty) {
        _selectedCategory = null;
      } else if (_selectedCategory == category) {
        _selectedCategory = null;
      } else {
        _selectedCategory = category;
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final context = _issuesKey.currentContext;
      if (context != null) {
        Scrollable.ensureVisible(
          context,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final filteredIssues = _filteredIssues();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text(
              'Контроль качества существующей БД',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: <Widget>[
                _MetricItem(
                  title: 'Всего вопросов в БД',
                  value: '${widget.report.totalQuestions}',
                ),
                _MetricItem(
                  title: 'Всего найдено проблем',
                  value: '${widget.report.totalIssues}',
                ),
                _MetricItem(
                  title: 'Пустой вопрос',
                  value: '${widget.report.missingQuestionTextCount}',
                ),
                _MetricItem(
                  title: 'Без правильного ответа',
                  value: '${widget.report.missingAnswerCount}',
                ),
                _MetricItem(
                  title: 'Нет вопрос. формулировки',
                  value: '${widget.report.missingQuestionMarkCount}',
                ),
                _MetricItem(
                  title: 'Непонятная формулировка',
                  value: '${widget.report.unclearQuestionTextCount}',
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Text(
              'Разбивка проблем по узлам (нажмите на узел)',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            if (widget.report.categories.isEmpty)
              const Text('Нет данных')
            else
              ...widget.report.categories
                  .take(20)
                  .map(
                    (row) => Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: row.issueCount == 0
                            ? null
                            : () => _selectCategory(row.category),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: _selectedCategory == row.category
                                  ? Theme.of(context).colorScheme.secondary
                                  : Colors.white24,
                            ),
                            color: _selectedCategory == row.category
                                ? Theme.of(context).colorScheme.secondary
                                      .withValues(alpha: 0.14)
                                : Colors.white.withValues(alpha: 0.02),
                          ),
                          child: Text(
                            '${row.category}: проблем ${row.issueCount}, всего вопросов ${row.totalQuestions}',
                          ),
                        ),
                      ),
                    ),
                  ),
            if (widget.report.categories.length > 20)
              Text(
                'Показаны первые 20 из ${widget.report.categories.length}.',
                style: TextStyle(color: Colors.grey.shade400),
              ),
            const SizedBox(height: 12),
            if (_selectedCategory != null) ...<Widget>[
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  Chip(label: Text('Фильтр: $_selectedCategory')),
                  OutlinedButton(
                    onPressed: () => _selectCategory(null),
                    child: const Text('Сбросить фильтр'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],
            Container(key: _issuesKey),
            Text(
              'Примеры проблемных вопросов (${filteredIssues.length})',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            if (filteredIssues.isEmpty)
              const Text('Проблемы не найдены')
            else
              ...filteredIssues.take(200).map((issue) {
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.white24),
                    color: Colors.orange.withValues(alpha: 0.08),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        issue.type.label,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 4),
                      SelectableText(issue.details),
                      const SizedBox(height: 4),
                      SelectableText('Категория: ${issue.category}'),
                      const SizedBox(height: 4),
                      SelectableText('Вопрос: ${issue.question.questionText}'),
                      SelectableText('Ответ: ${issue.question.correctAnswer}'),
                    ],
                  ),
                );
              }),
            if (filteredIssues.length > 200)
              Text(
                'Показаны первые 200 из ${filteredIssues.length}.',
                style: TextStyle(color: Colors.grey.shade400),
              ),
          ],
        ),
      ),
    );
  }
}

class _PureNewSection extends StatelessWidget {
  const _PureNewSection({required this.questions});

  final List<Question> questions;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'Чисто новые вопросы (${questions.length})',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            if (questions.isEmpty)
              const Text('Нет записей')
            else
              ...questions
                  .take(300)
                  .toList(growable: false)
                  .asMap()
                  .entries
                  .map((entry) {
                    final index = entry.key;
                    final question = entry.value;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          SelectableText(
                            '${index + 1}. ${question.questionText}',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          SelectableText('Ответ: ${question.correctAnswer}'),
                          if ((question.sourceFile ?? '').trim().isNotEmpty)
                            Text(
                              'Источник: ${question.sourceFile}',
                              style: TextStyle(
                                color: Colors.grey.shade400,
                                fontSize: 12,
                              ),
                            ),
                        ],
                      ),
                    );
                  }),
            if (questions.length > 300)
              Text(
                'Показаны первые 300 из ${questions.length}.',
                style: TextStyle(color: Colors.grey.shade400),
              ),
          ],
        ),
      ),
    );
  }
}
