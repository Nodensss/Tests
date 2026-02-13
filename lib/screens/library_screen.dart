import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/question.dart';
import '../state/app_state.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _category = 'Все';
  int? _difficulty;
  bool _onlyHard = false;
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
    final appState = context.watch<AppState>();
    final categories = appState.categories;
    if (!categories.contains(_category)) {
      _category = 'Все';
    }

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
                  'Поиск и фильтры',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    border: const OutlineInputBorder(),
                    labelText: 'Поиск',
                    suffixIcon: IconButton(
                      onPressed: _refresh,
                      icon: const Icon(Icons.search),
                    ),
                  ),
                  onSubmitted: (_) => _refresh(),
                ),
                const SizedBox(height: 8),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _category,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          labelText: 'Категория',
                        ),
                        items: categories
                            .map(
                              (c) => DropdownMenuItem<String>(
                                value: c,
                                child: Text(c),
                              ),
                            )
                            .toList(growable: false),
                        onChanged: (value) {
                          if (value == null) {
                            return;
                          }
                          setState(() {
                            _category = value;
                          });
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: DropdownButtonFormField<int?>(
                        initialValue: _difficulty,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          labelText: 'Сложность',
                        ),
                        items: const <DropdownMenuItem<int?>>[
                          DropdownMenuItem(value: null, child: Text('Все')),
                          DropdownMenuItem(value: 1, child: Text('1')),
                          DropdownMenuItem(value: 2, child: Text('2')),
                          DropdownMenuItem(value: 3, child: Text('3')),
                          DropdownMenuItem(value: 4, child: Text('4')),
                          DropdownMenuItem(value: 5, child: Text('5')),
                        ],
                        onChanged: (value) {
                          setState(() {
                            _difficulty = value;
                          });
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  value: _onlyHard,
                  onChanged: (value) {
                    setState(() {
                      _onlyHard = value;
                    });
                  },
                  title: const Text('Только сложные вопросы'),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    FilledButton.tonal(
                      onPressed: _refresh,
                      child: const Text('Обновить'),
                    ),
                    FilledButton.tonal(
                      onPressed: _questions.isEmpty ? null : _exportCsv,
                      child: const Text('Экспорт CSV'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Text(
                      'Вопросов: ${_questions.length}',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (_loading) ...<Widget>[
                      const SizedBox(width: 10),
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 8),
                _QuestionsTable(
                  questions: _questions,
                  onEdit: _showEditDialog,
                  onDelete: _deleteQuestion,
                ),
              ],
            ),
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
      category: _category,
      difficulty: _difficulty,
      searchQuery: _searchController.text.trim(),
      onlyHard: _onlyHard,
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _questions = data;
      _loading = false;
    });
  }

  Future<void> _showEditDialog(Question question) async {
    final competencyController = TextEditingController(
      text: question.competency ?? '',
    );
    final categoryController = TextEditingController(
      text: question.category ?? 'Без категории',
    );
    final subcategoryController = TextEditingController(
      text: question.subcategory ?? '',
    );
    int difficulty = question.difficulty;
    bool isHard = question.isHard;

    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Редактировать вопрос #${question.id}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              TextField(
                controller: competencyController,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'Компетенция',
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: categoryController,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'Категория',
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: subcategoryController,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'Подкатегория',
                ),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<int>(
                initialValue: difficulty,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'Сложность',
                ),
                items: const <DropdownMenuItem<int>>[
                  DropdownMenuItem(value: 1, child: Text('1')),
                  DropdownMenuItem(value: 2, child: Text('2')),
                  DropdownMenuItem(value: 3, child: Text('3')),
                  DropdownMenuItem(value: 4, child: Text('4')),
                  DropdownMenuItem(value: 5, child: Text('5')),
                ],
                onChanged: (value) {
                  if (value == null) {
                    return;
                  }
                  setDialogState(() {
                    difficulty = value;
                  });
                },
              ),
              const SizedBox(height: 8),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: isHard,
                onChanged: (value) {
                  if (value == null) {
                    return;
                  }
                  setDialogState(() {
                    isHard = value;
                  });
                },
                title: const Text('Сложный вопрос'),
              ),
            ],
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () async {
                final appState = this.context.read<AppState>();
                final navigator = Navigator.of(context);
                if (question.id == null) {
                  return;
                }
                await appState.updateQuestionCategory(
                  questionId: question.id!,
                  category: categoryController.text.trim().isEmpty
                      ? 'Без категории'
                      : categoryController.text.trim(),
                  competency: competencyController.text.trim().isEmpty
                      ? null
                      : competencyController.text.trim(),
                  subcategory: subcategoryController.text.trim(),
                  difficulty: difficulty,
                );
                await appState.setQuestionHardStatus(
                  questionId: question.id!,
                  isHard: isHard,
                );
                if (!mounted) {
                  return;
                }
                navigator.pop();
                await _refresh();
              },
              child: const Text('Сохранить'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteQuestion(Question question) async {
    final appState = context.read<AppState>();
    if (question.id == null) {
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удаление'),
        content: Text('Удалить вопрос #${question.id}?'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Нет'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Да'),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }
    await appState.deleteQuestion(question.id!);
    if (!mounted) {
      return;
    }
    await _refresh();
  }

  Future<void> _exportCsv() async {
    final rows = <List<String>>[
      <String>[
        'id',
        'question_text',
        'correct_answer',
        'wrong_answer_1',
        'wrong_answer_2',
        'wrong_answer_3',
        'competency',
        'category',
        'subcategory',
        'difficulty',
        'source_file',
        'is_hard',
      ],
      ..._questions.map(
        (q) => <String>[
          '${q.id ?? ''}',
          q.questionText,
          q.correctAnswer,
          q.wrongAnswers.isNotEmpty ? q.wrongAnswers[0] : '',
          q.wrongAnswers.length > 1 ? q.wrongAnswers[1] : '',
          q.wrongAnswers.length > 2 ? q.wrongAnswers[2] : '',
          q.competency ?? '',
          q.category ?? '',
          q.subcategory ?? '',
          '${q.difficulty}',
          q.sourceFile ?? '',
          q.isHard ? '1' : '0',
        ],
      ),
    ];

    final csv = rows
        .map(
          (row) =>
              row.map((value) => '"${value.replaceAll('"', '""')}"').join(','),
        )
        .join('\n');

    if (kIsWeb) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Экспорт на web пока не поддержан в этом MVP.'),
        ),
      );
      return;
    }

    final path = await FilePicker.platform.saveFile(
      dialogTitle: 'Сохранить CSV',
      fileName: 'questions_export.csv',
      bytes: utf8.encode(csv),
    );
    if (path == null) {
      return;
    }
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Файл сохранён: $path')));
  }
}

class _QuestionsTable extends StatelessWidget {
  const _QuestionsTable({
    required this.questions,
    required this.onEdit,
    required this.onDelete,
  });

  final List<Question> questions;
  final ValueChanged<Question> onEdit;
  final ValueChanged<Question> onDelete;

  @override
  Widget build(BuildContext context) {
    if (questions.isEmpty) {
      return const Text('Нет данных.');
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columnSpacing: 12,
        columns: const <DataColumn>[
          DataColumn(label: Text('ID')),
          DataColumn(label: Text('Question')),
          DataColumn(label: Text('Competency')),
          DataColumn(label: Text('Category')),
          DataColumn(label: Text('Difficulty')),
          DataColumn(label: Text('Hard')),
          DataColumn(label: Text('Actions')),
        ],
        rows: questions
            .take(300)
            .map(
              (q) => DataRow(
                cells: <DataCell>[
                  DataCell(Text('${q.id ?? ''}')),
                  DataCell(
                    SizedBox(
                      width: 340,
                      child: Text(
                        q.questionText,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  DataCell(
                    SizedBox(
                      width: 260,
                      child: Text(
                        q.competency ?? '—',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  DataCell(Text(q.category ?? '—')),
                  DataCell(Text('${q.difficulty}')),
                  DataCell(
                    Icon(
                      q.isHard ? Icons.bookmark : Icons.bookmark_border,
                      size: 18,
                    ),
                  ),
                  DataCell(
                    Wrap(
                      spacing: 6,
                      children: <Widget>[
                        TextButton(
                          onPressed: () => onEdit(q),
                          child: const Text('Edit'),
                        ),
                        TextButton(
                          onPressed: () => onDelete(q),
                          child: const Text('Delete'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            )
            .toList(growable: false),
      ),
    );
  }
}
