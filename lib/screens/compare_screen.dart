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
