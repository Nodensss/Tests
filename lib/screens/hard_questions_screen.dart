import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/question.dart';
import '../state/app_state.dart';

class HardQuestionsScreen extends StatefulWidget {
  const HardQuestionsScreen({super.key});

  @override
  State<HardQuestionsScreen> createState() => _HardQuestionsScreenState();
}

class _HardQuestionsScreenState extends State<HardQuestionsScreen> {
  final TextEditingController _searchController = TextEditingController();
  List<Question> _questions = <Question>[];
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
      children: <Widget>[
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text(
                  'База сложных вопросов',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    border: const OutlineInputBorder(),
                    labelText: 'Поиск по сложным вопросам',
                    suffixIcon: IconButton(
                      onPressed: _refresh,
                      icon: const Icon(Icons.search),
                    ),
                  ),
                  onSubmitted: (_) => _refresh(),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    FilledButton.tonalIcon(
                      onPressed: _refresh,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Обновить'),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: _questions.isEmpty ? null : _copyAllQuestions,
                      icon: const Icon(Icons.copy_all_outlined),
                      label: const Text('Копировать все'),
                    ),
                    if (_questions.isNotEmpty)
                      Chip(label: Text('Всего: ${_questions.length}')),
                    if (_loading)
                      const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        if (_questions.isEmpty && !_loading)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(14),
              child: Text(
                'Сложных вопросов пока нет. Добавь их из режима Study кнопкой "В сложные".',
              ),
            ),
          )
        else
          ..._questions.map(
            (q) => _HardQuestionCard(
              question: q,
              onRemove: () => _removeFromHard(q),
              onCopy: () => _copyOneQuestion(q),
            ),
          ),
      ],
    );
  }

  Future<void> _refresh() async {
    final appState = context.read<AppState>();
    setState(() {
      _loading = true;
    });
    final data = await appState.loadLibrary(
      onlyHard: true,
      searchQuery: _searchController.text.trim(),
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _questions = data;
      _loading = false;
    });
  }

  Future<void> _removeFromHard(Question question) async {
    final questionId = question.id;
    if (questionId == null) {
      return;
    }
    final appState = context.read<AppState>();
    await appState.setQuestionHardStatus(questionId: questionId, isHard: false);
    if (!mounted) {
      return;
    }
    await _refresh();
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Вопрос убран из сложных')));
  }

  Future<void> _copyOneQuestion(Question question) async {
    final text = _formatQuestionForCopy(question);
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Вопрос скопирован')));
  }

  Future<void> _copyAllQuestions() async {
    final payload = _questions
        .asMap()
        .entries
        .map(
          (entry) => _formatQuestionForCopy(entry.value, index: entry.key + 1),
        )
        .join('\n\n====================\n\n');
    await Clipboard.setData(ClipboardData(text: payload));
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Скопировано сложных вопросов: ${_questions.length}'),
      ),
    );
  }

  String _formatQuestionForCopy(Question question, {int? index}) {
    final wrong = question.wrongAnswers
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
    final lines = <String>[
      if (index != null) '$index.',
      'Вопрос: ${question.questionText}',
      'Правильный ответ: ${question.correctAnswer}',
      if ((question.competency ?? '').trim().isNotEmpty)
        'Компетенция: ${question.competency}',
      if ((question.category ?? '').trim().isNotEmpty)
        'Категория: ${question.category}',
      'Сложность: ${question.difficulty}',
      if (wrong.isNotEmpty) 'Неправильные варианты:',
      ...wrong.map((item) => '- $item'),
      if ((question.sourceFile ?? '').trim().isNotEmpty)
        'Источник: ${question.sourceFile}',
    ];
    return lines.join('\n');
  }
}

class _HardQuestionCard extends StatelessWidget {
  const _HardQuestionCard({
    required this.question,
    required this.onRemove,
    required this.onCopy,
  });

  final Question question;
  final VoidCallback onRemove;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    final wrong = question.wrongAnswers
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              question.questionText,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: <Widget>[
                if ((question.competency ?? '').trim().isNotEmpty)
                  Chip(label: Text(question.competency!)),
                Chip(label: Text(question.category ?? 'Без категории')),
                Chip(label: Text('Difficulty ${question.difficulty}')),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Правильный ответ: ${question.correctAnswer}',
              style: const TextStyle(color: Colors.greenAccent),
            ),
            if (wrong.isNotEmpty) ...<Widget>[
              const SizedBox(height: 8),
              Text(
                'Неправильные варианты:',
                style: TextStyle(color: Colors.grey.shade300),
              ),
              const SizedBox(height: 4),
              ...wrong.map((item) => Text('• $item')),
            ],
            if ((question.sourceFile ?? '').trim().isNotEmpty) ...<Widget>[
              const SizedBox(height: 8),
              Text(
                'Источник: ${question.sourceFile}',
                style: TextStyle(color: Colors.grey.shade400, fontSize: 12),
              ),
            ],
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  TextButton.icon(
                    onPressed: onCopy,
                    icon: const Icon(Icons.copy_outlined),
                    label: const Text('Копировать'),
                  ),
                  TextButton.icon(
                    onPressed: onRemove,
                    icon: const Icon(Icons.bookmark_remove_outlined),
                    label: const Text('Убрать из сложных'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
