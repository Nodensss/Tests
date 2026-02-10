import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';

class UploadScreen extends StatefulWidget {
  const UploadScreen({super.key});

  @override
  State<UploadScreen> createState() => _UploadScreenState();
}

class _UploadScreenState extends State<UploadScreen> {
  List<PlatformFile> _selectedFiles = <PlatformFile>[];

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final questions = appState.uploadQuestions;

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
                  'Импорт Excel файлов',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  'AI provider: ${appState.aiProvider.label}',
                  style: TextStyle(color: Colors.grey.shade300, fontSize: 12),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    FilledButton.icon(
                      onPressed: appState.busy ? null : _pickFiles,
                      icon: const Icon(Icons.attach_file),
                      label: const Text('Выбрать файлы'),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: appState.busy || _selectedFiles.isEmpty
                          ? null
                          : _parseFiles,
                      icon: const Icon(Icons.table_chart_outlined),
                      label: const Text('Разобрать'),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: appState.busy || questions.isEmpty
                          ? null
                          : appState.categorizeUploadedQuestions,
                      icon: const Icon(Icons.auto_awesome_outlined),
                      label: const Text('Категоризировать AI'),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: appState.busy || questions.isEmpty
                          ? null
                          : () async {
                              final inserted = await appState
                                  .saveUploadedQuestions();
                              if (!context.mounted) {
                                return;
                              }
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    'Сохранено/обновлено вопросов: $inserted',
                                  ),
                                ),
                              );
                            },
                      icon: const Icon(Icons.save_outlined),
                      label: const Text('Сохранить в БД'),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: appState.busy
                          ? null
                          : () async {
                              final updated = await appState
                                  .fillMissingCompetenciesInDatabase();
                              if (!context.mounted) {
                                return;
                              }
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    'Заполнено компетенций у вопросов: $updated',
                                  ),
                                ),
                              );
                            },
                      icon: const Icon(Icons.rule_folder_outlined),
                      label: const Text('Заполнить пустые компетенции'),
                    ),
                    TextButton.icon(
                      onPressed: appState.busy
                          ? null
                          : () {
                              setState(() {
                                _selectedFiles = <PlatformFile>[];
                              });
                              appState.clearUploadState();
                            },
                      icon: const Icon(Icons.clear_all),
                      label: const Text('Очистить'),
                    ),
                    TextButton.icon(
                      onPressed: appState.busy
                          ? null
                          : () => _confirmResetDatabase(context, appState),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.redAccent,
                      ),
                      icon: const Icon(Icons.delete_forever_outlined),
                      label: const Text('Сбросить БД'),
                    ),
                  ],
                ),
                if (appState.busy) ...<Widget>[
                  const SizedBox(height: 12),
                  LinearProgressIndicator(
                    value: appState.busyProgress,
                    minHeight: 4,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    appState.busyTitle.isEmpty
                        ? 'Обработка...'
                        : appState.busyTitle,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  if (appState.busyDetails.trim().isNotEmpty) ...<Widget>[
                    const SizedBox(height: 2),
                    Text(
                      appState.busyDetails,
                      style: TextStyle(
                        color: Colors.grey.shade300,
                        fontSize: 12,
                      ),
                    ),
                  ],
                  if (appState.busyProgress != null) ...<Widget>[
                    const SizedBox(height: 2),
                    Text(
                      'Прогресс: ${(appState.busyProgress! * 100).toStringAsFixed(1)}%',
                      style: TextStyle(
                        color: Colors.grey.shade300,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
                if (_selectedFiles.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 10),
                  Text(
                    'Выбрано файлов: ${_selectedFiles.length}',
                    style: TextStyle(color: Colors.grey.shade300),
                  ),
                ],
                if (appState.errorMessage != null) ...<Widget>[
                  const SizedBox(height: 10),
                  Text(
                    appState.errorMessage!,
                    style: const TextStyle(color: Colors.redAccent),
                  ),
                ],
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
                      'Найдено вопросов: ${questions.length}',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 10),
                    if (appState.uploadCategorized)
                      const Chip(
                        label: Text('AI categorized'),
                        visualDensity: VisualDensity.compact,
                      ),
                    if (appState.uploadSaved)
                      const Chip(
                        label: Text('Saved'),
                        visualDensity: VisualDensity.compact,
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                _PreviewTable(),
              ],
            ),
          ),
        ),
        if (appState.uploadWarnings.isNotEmpty) ...<Widget>[
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Text(
                    'Предупреждения',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  ...appState.uploadWarnings
                      .take(12)
                      .map(
                        (warning) => Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text('• $warning'),
                        ),
                      ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _pickFiles() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      withData: true,
      type: FileType.custom,
      allowedExtensions: const <String>['xlsx', 'xls'],
    );
    if (result == null) {
      return;
    }
    setState(() {
      _selectedFiles = result.files;
    });
  }

  Future<void> _parseFiles() async {
    final appState = context.read<AppState>();
    await appState.parseFiles(_selectedFiles);
  }

  Future<void> _confirmResetDatabase(
    BuildContext context,
    AppState appState,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Сбросить всю базу?'),
        content: const Text(
          'Будут удалены все вопросы, статистика, учебные сессии и AI-кэш. Действие необратимо.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
            ),
            child: const Text('Удалить всё'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) {
      return;
    }

    await appState.resetDatabase();
    if (!context.mounted) {
      return;
    }

    if (appState.errorMessage == null) {
      setState(() {
        _selectedFiles = <PlatformFile>[];
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('База очищена. Можно начать с нуля.')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(appState.errorMessage!),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }
}

class _PreviewTable extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final questions = context
        .watch<AppState>()
        .uploadQuestions
        .take(10)
        .toList();
    if (questions.isEmpty) {
      return const Text('Данных пока нет.');
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columns: const <DataColumn>[
          DataColumn(label: Text('Question')),
          DataColumn(label: Text('Correct')),
          DataColumn(label: Text('Competency')),
          DataColumn(label: Text('Category')),
          DataColumn(label: Text('Difficulty')),
          DataColumn(label: Text('Source')),
        ],
        rows: questions
            .map(
              (q) => DataRow(
                cells: <DataCell>[
                  DataCell(SizedBox(width: 320, child: Text(q.questionText))),
                  DataCell(SizedBox(width: 180, child: Text(q.correctAnswer))),
                  DataCell(
                    SizedBox(width: 260, child: Text(q.competency ?? '—')),
                  ),
                  DataCell(Text(q.category ?? '—')),
                  DataCell(Text('${q.difficulty}')),
                  DataCell(Text(q.sourceFile ?? '—')),
                ],
              ),
            )
            .toList(growable: false),
      ),
    );
  }
}
