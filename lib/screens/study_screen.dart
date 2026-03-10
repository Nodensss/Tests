import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/question.dart';
import '../services/quiz_engine.dart';
import '../state/app_state.dart';

enum _FullscreenMenuAction { explain, memoryTip, reset, exit }

class StudyScreen extends StatefulWidget {
  const StudyScreen({super.key, this.immersiveMode = false});

  final bool immersiveMode;

  @override
  State<StudyScreen> createState() => _StudyScreenState();
}

class _StudyScreenState extends State<StudyScreen> {
  StudyMode _mode = StudyMode.quiz;
  List<String> _selectedCategories = <String>[];
  int? _difficulty;
  int _questionCount = 20;
  int _availableQuestions = 0;
  bool _availableQuestionsLoading = false;
  bool _hasLoadedAvailableQuestions = false;
  bool _useAllQuestions = false;
  bool _onlyMultiSelect = false;
  int _countRequestId = 0;

  final Map<String, List<String>> _optionsCache = <String, List<String>>{};
  final Set<String> _selectedOptions = <String>{};
  final TextEditingController _multiSelectInputController =
      TextEditingController();
  String? _explanation;
  String? _memoryTip;
  bool _isSyncingMultiSelectInput = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _refreshAvailableCount(context.read<AppState>());
    });
  }

  @override
  void dispose() {
    _multiSelectInputController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final session = appState.studySession;

    if (session == null) {
      if (!_hasLoadedAvailableQuestions && !_availableQuestionsLoading) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) {
            return;
          }
          _refreshAvailableCount(context.read<AppState>());
        });
      }
      return _buildStartPanel(context, appState);
    }
    if (session.isCompleted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        appState.finalizeSessionIfNeeded();
      });
      return _buildSessionSummary(context, appState);
    }
    return _buildActiveSession(context, appState);
  }

  Widget _buildStartPanel(BuildContext context, AppState appState) {
    if (widget.immersiveMode) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    const Text(
                      'Полноэкранный режим викторины',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Сессия не запущена. Запустите тест в обычном режиме, затем откройте полноэкранный режим.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: () => Navigator.of(context).maybePop(),
                      icon: const Icon(Icons.fullscreen_exit),
                      label: const Text('Выйти из полноэкранного режима'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    final available = _availableQuestions;
    final maxSelectable = available > 0 ? available : 1;
    final displayedCount = _useAllQuestions
        ? maxSelectable
        : _questionCount.clamp(1, maxSelectable);

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
                  'Настройка сессии',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<StudyMode>(
                  initialValue: _mode,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: 'Режим',
                  ),
                  items: const <DropdownMenuItem<StudyMode>>[
                    DropdownMenuItem(
                      value: StudyMode.quiz,
                      child: Text('Quiz'),
                    ),
                    DropdownMenuItem(
                      value: StudyMode.flashcards,
                      child: Text('Flashcards'),
                    ),
                    DropdownMenuItem(
                      value: StudyMode.review,
                      child: Text('Review'),
                    ),
                    DropdownMenuItem(
                      value: StudyMode.categoryDrill,
                      child: Text('Category Drill'),
                    ),
                    DropdownMenuItem(
                      value: StudyMode.weakSpots,
                      child: Text('Weak Spots'),
                    ),
                    DropdownMenuItem(
                      value: StudyMode.hardQuestions,
                      child: Text('Hard Questions'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value == null) {
                      return;
                    }
                    setState(() {
                      _mode = value;
                      _useAllQuestions = false;
                    });
                    _refreshAvailableCount(appState);
                  },
                ),
                const SizedBox(height: 10),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final compact = constraints.maxWidth < 900;
                    if (compact) {
                      return Column(
                        children: <Widget>[
                          _buildCategoryField(appState),
                          const SizedBox(height: 10),
                          _buildDifficultyField(appState),
                        ],
                      );
                    }
                    return Row(
                      children: <Widget>[
                        Expanded(child: _buildCategoryField(appState)),
                        const SizedBox(width: 10),
                        Expanded(child: _buildDifficultyField(appState)),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 10),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  value: _onlyMultiSelect,
                  onChanged: _mode == StudyMode.review
                      ? null
                      : (value) {
                          setState(() {
                            _onlyMultiSelect = value;
                            _useAllQuestions = false;
                          });
                          _refreshAvailableCount(appState);
                        },
                  title: const Text('Только вопросы с несколькими ответами'),
                  subtitle: const Text(
                    'Показывать только вопросы, где нужно выбрать несколько правильных вариантов.',
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: <Widget>[
                    Text('Доступно вопросов: $available'),
                    if (_availableQuestionsLoading) ...<Widget>[
                      const SizedBox(width: 8),
                      const SizedBox(
                        height: 16,
                        width: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 6),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  value: _useAllQuestions,
                  onChanged: available <= 0
                      ? null
                      : (value) {
                          setState(() {
                            _useAllQuestions = value;
                            if (!value) {
                              _questionCount = _questionCount.clamp(
                                1,
                                maxSelectable,
                              );
                            }
                          });
                        },
                  title: Text('Выбрать все вопросы ($maxSelectable)'),
                ),
                if (!_useAllQuestions)
                  Row(
                    children: <Widget>[
                      const Text('Количество вопросов:'),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Slider(
                          value: displayedCount.toDouble(),
                          min: 1,
                          max: maxSelectable.toDouble(),
                          label: '$displayedCount',
                          onChanged: available <= 0
                              ? null
                              : (value) {
                                  setState(() {
                                    _questionCount = value.round().clamp(
                                      1,
                                      maxSelectable,
                                    );
                                  });
                                },
                        ),
                      ),
                      Text('$displayedCount'),
                    ],
                  )
                else
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Text('Будут выбраны все $maxSelectable вопросов'),
                  ),
                Row(
                  children: <Widget>[
                    FilledButton.tonalIcon(
                      onPressed: available <= 0
                          ? null
                          : () {
                              setState(() {
                                _useAllQuestions = true;
                              });
                            },
                      icon: const Icon(Icons.select_all),
                      label: const Text('Выбрать все'),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                FilledButton.icon(
                  onPressed: appState.busy || displayedCount <= 0
                      ? null
                      : () async {
                          final targetCount = _useAllQuestions
                              ? maxSelectable
                              : displayedCount;
                          final selectedCategories =
                              _resolvedSelectedCategories(appState);
                          final error = await appState.startStudySession(
                            mode: _mode,
                            totalQuestions: targetCount,
                            categories: selectedCategories,
                            difficulty: _difficulty,
                            onlyMultiSelect: _onlyMultiSelect,
                          );
                          if (!context.mounted) {
                            return;
                          }
                          if (error != null) {
                            ScaffoldMessenger.of(
                              context,
                            ).showSnackBar(SnackBar(content: Text(error)));
                          } else {
                            _selectedOptions.clear();
                            _optionsCache.clear();
                            _explanation = null;
                            _memoryTip = null;
                          }
                        },
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Начать'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCategoryField(AppState appState) {
    final allCategories = appState.categories
        .where((item) => item.trim().isNotEmpty && item != 'Все')
        .toList(growable: false);
    final selected = _selectedCategories
        .where(allCategories.contains)
        .toList(growable: false);

    return InputDecorator(
      decoration: const InputDecoration(
        border: OutlineInputBorder(),
        labelText: 'Компетенции',
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              FilledButton.tonalIcon(
                onPressed: allCategories.isEmpty
                    ? null
                    : () => _pickCategories(appState, allCategories),
                icon: const Icon(Icons.filter_alt_outlined),
                label: const Text('Выбрать'),
              ),
              if (selected.isNotEmpty)
                OutlinedButton.icon(
                  onPressed: () {
                    setState(() {
                      _selectedCategories = <String>[];
                      _useAllQuestions = false;
                    });
                    _refreshAvailableCount(appState);
                  },
                  icon: const Icon(Icons.clear),
                  label: const Text('Сбросить'),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (selected.isEmpty)
            const Text('Все категории')
          else
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: selected
                  .map((category) => Chip(label: Text(category)))
                  .toList(growable: false),
            ),
        ],
      ),
    );
  }

  Widget _buildDifficultyField(AppState appState) {
    return DropdownButtonFormField<int?>(
      initialValue: _difficulty,
      isExpanded: true,
      decoration: const InputDecoration(
        border: OutlineInputBorder(),
        labelText: 'Сложность',
      ),
      items: const <DropdownMenuItem<int?>>[
        DropdownMenuItem<int?>(value: null, child: Text('Все')),
        DropdownMenuItem<int?>(value: 1, child: Text('1')),
        DropdownMenuItem<int?>(value: 2, child: Text('2')),
        DropdownMenuItem<int?>(value: 3, child: Text('3')),
        DropdownMenuItem<int?>(value: 4, child: Text('4')),
        DropdownMenuItem<int?>(value: 5, child: Text('5')),
      ],
      onChanged: (value) {
        setState(() {
          _difficulty = value;
          _useAllQuestions = false;
        });
        _refreshAvailableCount(appState);
      },
    );
  }

  Future<void> _pickCategories(
    AppState appState,
    List<String> allCategories,
  ) async {
    final initial = _selectedCategories.where(allCategories.contains).toSet();
    final selected = Set<String>.from(initial);

    final result = await showDialog<List<String>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Выберите компетенции'),
          content: SizedBox(
            width: 760,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    OutlinedButton(
                      onPressed: () {
                        setDialogState(() {
                          selected
                            ..clear()
                            ..addAll(allCategories);
                        });
                      },
                      child: const Text('Выбрать все'),
                    ),
                    OutlinedButton(
                      onPressed: () {
                        setDialogState(selected.clear);
                      },
                      child: const Text('Очистить'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 360,
                  child: Scrollbar(
                    thumbVisibility: true,
                    child: ListView.builder(
                      itemCount: allCategories.length,
                      itemBuilder: (context, index) {
                        final item = allCategories[index];
                        final checked = selected.contains(item);
                        return CheckboxListTile(
                          dense: true,
                          value: checked,
                          title: Text(item),
                          onChanged: (value) {
                            setDialogState(() {
                              if (value == true) {
                                selected.add(item);
                              } else {
                                selected.remove(item);
                              }
                            });
                          },
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () {
                final ordered = allCategories
                    .where(selected.contains)
                    .toList(growable: false);
                Navigator.of(context).pop(ordered);
              },
              child: const Text('Применить'),
            ),
          ],
        ),
      ),
    );

    if (!mounted || result == null) {
      return;
    }

    final normalized = result.length == allCategories.length
        ? <String>[]
        : result;
    setState(() {
      _selectedCategories = normalized;
      _useAllQuestions = false;
    });
    await _refreshAvailableCount(appState);
  }

  Widget _buildActiveSession(BuildContext context, AppState appState) {
    final session = appState.studySession!;
    final question = session.currentQuestion;
    final sessionIndex = session.currentIndex;
    final answeredCurrent = session.mode == StudyMode.flashcards
        ? session.answeredCurrent
        : session.quizSelectedOptions.containsKey(sessionIndex);
    final currentIsCorrect = session.mode == StudyMode.flashcards
        ? session.lastIsCorrect
        : (session.quizIsCorrectByIndex[sessionIndex] ?? false);
    final progress = session.questions.isEmpty
        ? 0.0
        : session.currentIndex / session.questions.length;

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
      children: <Widget>[
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Align(
                  alignment: Alignment.centerRight,
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: <Widget>[
                      if (!widget.immersiveMode &&
                          session.mode != StudyMode.flashcards)
                        OutlinedButton.icon(
                          onPressed: session.currentIndex > 0
                              ? () {
                                  appState.previousStudyQuestion();
                                  setState(() {
                                    _syncLocalFromSession(
                                      appState.studySession,
                                    );
                                  });
                                }
                              : null,
                          icon: const Icon(Icons.arrow_back),
                          label: const Text('Назад'),
                        ),
                      if (!widget.immersiveMode)
                        OutlinedButton.icon(
                          onPressed: () => _openFullscreenQuiz(context),
                          icon: const Icon(Icons.fullscreen),
                          label: const Text('Полный экран'),
                        ),
                      if (!widget.immersiveMode)
                        OutlinedButton.icon(
                          onPressed: () => _toggleCurrentHardQuestion(appState),
                          icon: Icon(
                            question.isHard
                                ? Icons.bookmark_remove_outlined
                                : Icons.bookmark_add_outlined,
                          ),
                          label: Text(
                            question.isHard ? 'Убрать из сложных' : 'В сложные',
                          ),
                        ),
                      if (!widget.immersiveMode)
                        OutlinedButton.icon(
                          onPressed: () =>
                              _confirmResetSession(context, appState),
                          icon: const Icon(Icons.restart_alt),
                          label: const Text('Сбросить тест'),
                        ),
                      if (widget.immersiveMode)
                        PopupMenuButton<_FullscreenMenuAction>(
                          tooltip: 'Меню',
                          icon: const Icon(Icons.more_horiz),
                          onSelected: (action) => _handleFullscreenMenuAction(
                            action,
                            context,
                            appState,
                          ),
                          itemBuilder: (context) =>
                              const <PopupMenuEntry<_FullscreenMenuAction>>[
                                PopupMenuItem<_FullscreenMenuAction>(
                                  value: _FullscreenMenuAction.explain,
                                  child: Text('Объяснить (AI)'),
                                ),
                                PopupMenuItem<_FullscreenMenuAction>(
                                  value: _FullscreenMenuAction.memoryTip,
                                  child: Text('Как запомнить (AI)'),
                                ),
                                PopupMenuDivider(),
                                PopupMenuItem<_FullscreenMenuAction>(
                                  value: _FullscreenMenuAction.reset,
                                  child: Text('Сбросить тест'),
                                ),
                                PopupMenuItem<_FullscreenMenuAction>(
                                  value: _FullscreenMenuAction.exit,
                                  child: Text('Выйти из полноэкранного режима'),
                                ),
                              ],
                        ),
                    ],
                  ),
                ),
                LinearProgressIndicator(value: progress),
                const SizedBox(height: 8),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        'Вопрос ${session.currentIndex + 1} / ${session.questions.length}',
                        style: TextStyle(color: Colors.grey.shade300),
                      ),
                    ),
                    if (session.questions.length > 1)
                      IconButton(
                        onPressed: () =>
                            _showQuestionJumpDialog(context, appState),
                        tooltip: 'Перейти к вопросу',
                        icon: const Icon(Icons.list_alt_outlined),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                SelectableText(
                  question.questionText,
                  style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: <Widget>[
                    if (answeredCurrent && session.mode != StudyMode.flashcards)
                      Chip(
                        label: Text(currentIsCorrect ? 'Верно' : 'Неверно'),
                        backgroundColor: currentIsCorrect
                            ? Colors.green.withValues(alpha: 0.2)
                            : Colors.red.withValues(alpha: 0.2),
                        side: BorderSide(
                          color: currentIsCorrect
                              ? Colors.greenAccent
                              : Colors.redAccent,
                        ),
                      ),
                    if (widget.immersiveMode) ...<Widget>[
                      if (((question.competency ?? '').trim().isNotEmpty))
                        Chip(label: Text(question.competency!))
                      else if (((question.sourceFile ?? '').trim().isNotEmpty))
                        Chip(label: Text(question.sourceFile!)),
                    ] else ...<Widget>[
                      if ((question.competency ?? '').trim().isNotEmpty)
                        Chip(label: Text(question.competency!)),
                      Chip(label: Text(question.category ?? 'Без категории')),
                      Chip(label: Text('Difficulty ${question.difficulty}')),
                      if (question.isHard) const Chip(label: Text('Сложный')),
                    ],
                  ],
                ),
                if (!widget.immersiveMode) ...<Widget>[
                  const SizedBox(height: 8),
                  FilledButton.tonalIcon(
                    onPressed: () => _searchQuestionInWeb(question),
                    icon: const Icon(Icons.travel_explore_outlined),
                    label: const Text('Искать в интернете'),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        if (session.mode == StudyMode.flashcards)
          _buildFlashcards(context, appState)
        else
          _buildQuizLike(context, appState),
      ],
    );
  }

  Widget _buildQuizLike(BuildContext context, AppState appState) {
    final session = appState.studySession!;
    final question = session.currentQuestion;
    final index = session.currentIndex;
    final answeredCurrent = session.quizSelectedOptions.containsKey(index);
    final selectedFromHistory = appState.decodeSelectedAnswers(
      session.quizSelectedOptions[index],
    );
    final selectedOptions = answeredCurrent
        ? selectedFromHistory.toSet()
        : _selectedOptions;
    final currentTime = answeredCurrent
        ? (session.quizTimeSecondsByIndex[index] ?? session.lastTimeSeconds)
        : session.lastTimeSeconds;

    final cacheKey = '${question.id ?? session.currentIndex}';
    final options = _optionsCache.putIfAbsent(
      cacheKey,
      () => appState.quizEngine.buildOptions(
        question,
        fallbackPool: session.questions,
      ),
    );
    final correctOptions = question.allCorrectAnswers.toSet();
    final selectedIndexes = <int>[];
    for (var i = 0; i < options.length; i++) {
      if (selectedOptions.contains(options[i])) {
        selectedIndexes.add(i + 1);
      }
    }
    final selectedIndexesLabel = selectedIndexes.join(', ');
    if (question.isMultiSelect) {
      _syncMultiSelectInputValue(selectedIndexesLabel);
    } else {
      _syncMultiSelectInputValue('');
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            if (question.isMultiSelect) ...<Widget>[
              Text(
                'Выберите ${question.requiredCorrectAnswersCount} правильных вариантов',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.secondary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _multiSelectInputController,
                enabled: !answeredCurrent,
                keyboardType: TextInputType.number,
                inputFormatters: <TextInputFormatter>[
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9,\s]')),
                ],
                decoration: const InputDecoration(
                  labelText: 'Номера ответов через запятую',
                  hintText: 'Например: 1, 3, 4, 7',
                  helperText: 'Можно вводить номера или нажимать по вариантам ниже',
                ),
                onChanged: answeredCurrent
                    ? null
                    : (value) => _handleMultiSelectInputChanged(value, options),
              ),
              const SizedBox(height: 10),
            ],
            Column(
              children: options.asMap().entries.map((entry) {
                final optionIndex = entry.key;
                final option = entry.value;
                return _buildAnswerOptionTile(
                  context: context,
                  optionNumber: optionIndex + 1,
                  text: option,
                  selected: selectedOptions.contains(option),
                  answered: answeredCurrent,
                  isCorrectOption: correctOptions.contains(option),
                  isChosenOption: selectedOptions.contains(option),
                    onTap: answeredCurrent
                        ? null
                        : () {
                            setState(() {
                              if (question.isMultiSelect) {
                              if (_selectedOptions.contains(option)) {
                                _selectedOptions.remove(option);
                                } else {
                                  _selectedOptions.add(option);
                                }
                                final updatedIndexes = <int>[];
                                for (var i = 0; i < options.length; i++) {
                                  if (_selectedOptions.contains(options[i])) {
                                    updatedIndexes.add(i + 1);
                                  }
                                }
                                _syncMultiSelectInputValue(
                                  updatedIndexes.join(', '),
                                );
                              } else {
                                _selectedOptions
                                  ..clear()
                                  ..add(option);
                              }
                          });
                        },
                );
              }).toList(growable: false),
            ),
            if (!answeredCurrent && question.isMultiSelect) ...<Widget>[
              const SizedBox(height: 4),
              Text(
                selectedIndexes.isEmpty
                    ? 'Выбрано: ничего'
                    : 'Выбрано: $selectedIndexesLabel',
              ),
            ],
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: answeredCurrent
                  ? FilledButton(
                      onPressed: () {
                        appState.nextStudyQuestion();
                        setState(() {
                          _syncLocalFromSession(appState.studySession);
                        });
                      },
                      child: const Text('Следующий вопрос'),
                    )
                  : _buildSubmitAnswerButton(appState),
            ),
            const SizedBox(height: 10),
            if (widget.immersiveMode)
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  if (session.currentIndex > 0)
                    OutlinedButton.icon(
                      onPressed: () {
                        appState.previousStudyQuestion();
                        setState(() {
                          _syncLocalFromSession(appState.studySession);
                        });
                      },
                      icon: const Icon(Icons.arrow_back),
                      label: const Text('Назад'),
                    ),
                  OutlinedButton.icon(
                    onPressed: () => _toggleCurrentHardQuestion(appState),
                    icon: Icon(
                      question.isHard
                          ? Icons.bookmark_remove_outlined
                          : Icons.bookmark_add_outlined,
                    ),
                    label: Text(
                      question.isHard ? 'Убрать из сложных' : 'В сложные',
                    ),
                  ),
                ],
              )
            else if (answeredCurrent) ...<Widget>[
              const SizedBox(height: 4),
              Text('Время: ${currentTime.toStringAsFixed(1)} сек'),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  FilledButton.tonal(
                    onPressed: () async {
                      final explanation = await appState
                          .explainCurrentQuestion();
                      if (!mounted) {
                        return;
                      }
                      setState(() {
                        _explanation = explanation;
                      });
                    },
                    child: const Text('Объяснить (AI)'),
                  ),
                  FilledButton.tonal(
                    onPressed: () async {
                      final tip = await appState
                          .buildMemoryTipForCurrentQuestion();
                      if (!mounted) {
                        return;
                      }
                      setState(() {
                        _memoryTip = tip;
                      });
                    },
                    child: const Text('Как запомнить (AI)'),
                  ),
                ],
              ),
              if ((_explanation ?? '').isNotEmpty) ...<Widget>[
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blueGrey.withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: SelectableText(_explanation!),
                ),
              ],
              if ((_memoryTip ?? '').isNotEmpty) ...<Widget>[
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.teal.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: SelectableText(_memoryTip!),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildFlashcards(BuildContext context, AppState appState) {
    final session = appState.studySession!;
    final question = session.currentQuestion;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            if (!session.showAnswer)
              FilledButton(
                onPressed: appState.revealFlashcardAnswer,
                child: const Text('Показать ответ'),
              )
            else ...<Widget>[
              SelectableText(
                question.correctAnswer,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (question.correctAnswer.trim().length > 120)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: () => _showFullTextDialog(
                      title: 'Полный ответ',
                      text: question.correctAnswer,
                    ),
                    child: const Text('Открыть полностью'),
                  ),
                ),
              const SizedBox(height: 8),
              if (!session.answeredCurrent)
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    FilledButton.tonal(
                      onPressed: () => appState.answerFlashcardLabel('Знал'),
                      child: const Text('Знал'),
                    ),
                    FilledButton.tonal(
                      onPressed: () =>
                          appState.answerFlashcardLabel('Частично'),
                      child: const Text('Частично'),
                    ),
                    FilledButton.tonal(
                      onPressed: () => appState.answerFlashcardLabel('Не знал'),
                      child: const Text('Не знал'),
                    ),
                  ],
                )
              else ...<Widget>[
                Text(
                  session.lastIsCorrect ? '✅ Засчитано' : '🟠 Повторить позже',
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    FilledButton.tonal(
                      onPressed: () async {
                        final tip = await appState
                            .buildMemoryTipForCurrentQuestion();
                        if (!mounted) {
                          return;
                        }
                        setState(() {
                          _memoryTip = tip;
                        });
                      },
                      child: const Text('Как запомнить (AI)'),
                    ),
                    FilledButton(
                      onPressed: () {
                        setState(() {
                          _memoryTip = null;
                        });
                        appState.nextStudyQuestion();
                      },
                      child: const Text('Следующая карточка'),
                    ),
                  ],
                ),
                if ((_memoryTip ?? '').isNotEmpty) ...<Widget>[
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.teal.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: SelectableText(_memoryTip!),
                  ),
                ],
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSessionSummary(BuildContext context, AppState appState) {
    final session = appState.studySession!;
    final wrongIndexes = appState.wrongQuizQuestionIndexes();
    final accuracy = session.questions.isEmpty
        ? 0.0
        : (session.correctCount / session.questions.length) * 100;
    final accuracyValue = (accuracy / 100).clamp(0.0, 1.0);

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
                  'Сессия завершена',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Text('Правильных: ${session.correctCount}'),
                Text('Всего: ${session.questions.length}'),
                Text(
                  'Процент правильных ответов: ${accuracy.toStringAsFixed(1)}% / 100%',
                ),
                const SizedBox(height: 8),
                LinearProgressIndicator(value: accuracyValue),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    FilledButton.tonal(
                      onPressed: () async {
                        final plan = await appState.generateStudyPlan();
                        if (!context.mounted) {
                          return;
                        }
                        showDialog<void>(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: const Text('AI Study Plan'),
                            content: SingleChildScrollView(child: Text(plan)),
                            actions: <Widget>[
                              TextButton(
                                onPressed: () => Navigator.of(context).pop(),
                                child: const Text('Close'),
                              ),
                            ],
                          ),
                        );
                      },
                      child: const Text('План на 7 дней'),
                    ),
                    FilledButton(
                      onPressed: () {
                        _resetCurrentSession(appState);
                      },
                      child: const Text('Новая сессия'),
                    ),
                    if (wrongIndexes.isNotEmpty)
                      FilledButton.tonalIcon(
                        onPressed: () async {
                          final error = await appState
                              .startRetryWrongAnswersSession();
                          if (!context.mounted) {
                            return;
                          }
                          if (error != null) {
                            ScaffoldMessenger.of(
                              context,
                            ).showSnackBar(SnackBar(content: Text(error)));
                          } else {
                            setState(() {
                              _selectedOptions.clear();
                              _explanation = null;
                              _memoryTip = null;
                              _optionsCache.clear();
                            });
                          }
                        },
                        icon: const Icon(Icons.replay),
                        label: Text('Тест по ошибкам (${wrongIndexes.length})'),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  'Ошибочные ответы (${wrongIndexes.length})',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                if (wrongIndexes.isEmpty)
                  const Text('Ошибок нет.')
                else
                  ...wrongIndexes.map((index) {
                    final question = session.questions[index];
                    final userAnswers = appState.decodeSelectedAnswers(
                      session.quizSelectedOptions[index],
                    );
                    final userAnswer = userAnswers.isEmpty
                        ? 'Нет ответа'
                        : userAnswers.join(' | ');
                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.redAccent),
                        color: Colors.redAccent.withValues(alpha: 0.08),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          SelectableText(
                            '${index + 1}. ${question.questionText}',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 4),
                          SelectableText('Ваш ответ: $userAnswer'),
                          SelectableText(
                            'Правильный ответ: ${question.allCorrectAnswers.join(' | ')}',
                          ),
                        ],
                      ),
                    );
                  }),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _refreshAvailableCount(AppState appState) async {
    final requestId = ++_countRequestId;
    setState(() {
      _availableQuestionsLoading = true;
    });
    try {
      final selectedCategories = _resolvedSelectedCategories(appState);
      final count = await appState.countQuestionsForMode(
        mode: _mode,
        categories: selectedCategories,
        difficulty: _difficulty,
        onlyMultiSelect: _onlyMultiSelect,
      );
      if (!mounted || requestId != _countRequestId) {
        return;
      }
      final normalized = count < 0 ? 0 : count;
      final maxSelectable = normalized > 0 ? normalized : 1;
      setState(() {
        _availableQuestions = normalized;
        _hasLoadedAvailableQuestions = true;
        _availableQuestionsLoading = false;
        if (_questionCount > maxSelectable) {
          _questionCount = maxSelectable;
        }
        if (_questionCount < 1) {
          _questionCount = 1;
        }
        if (normalized == 0) {
          _useAllQuestions = false;
        }
      });
    } catch (_) {
      if (!mounted || requestId != _countRequestId) {
        return;
      }
      setState(() {
        _availableQuestionsLoading = false;
        _hasLoadedAvailableQuestions = true;
      });
    }
  }

  List<String> _resolvedSelectedCategories(AppState appState) {
    final allowed = appState.categories.toSet();
    return _selectedCategories
        .map((item) => item.trim())
        .where(
          (item) => item.isNotEmpty && item != 'Все' && allowed.contains(item),
        )
        .toList(growable: false);
  }

  void _resetCurrentSession(AppState appState) {
    setState(() {
      _selectedOptions.clear();
      _explanation = null;
      _memoryTip = null;
      _optionsCache.clear();
    });
    appState.stopSession();
  }

  Future<void> _searchQuestionInWeb(Question question) async {
    final questionText = question.questionText.trim();
    final correctAnswer = question.correctAnswer.trim();
    final query = <String>[
      if (questionText.isNotEmpty) questionText,
      if (correctAnswer.isNotEmpty) correctAnswer,
    ].join(' ');
    if (query.isEmpty) {
      return;
    }
    final uri = Uri.parse(
      'https://www.google.com/search?q=${Uri.encodeQueryComponent(query)}',
    );
    final launched = await launchUrl(
      uri,
      mode: LaunchMode.platformDefault,
      webOnlyWindowName: '_blank',
    );
    if (!launched && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось открыть браузер')),
      );
    }
  }

  Future<void> _toggleCurrentHardQuestion(AppState appState) async {
    final result = await appState.toggleCurrentQuestionHard();
    if (!mounted || result == null) {
      return;
    }
    final message = result
        ? 'Вопрос добавлен в базу сложных'
        : 'Вопрос убран из базы сложных';
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _openFullscreenQuiz(BuildContext context) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const _QuizFullscreenPage()),
    );
  }

  Widget _buildAnswerOptionTile({
    required BuildContext context,
    required int optionNumber,
    required String text,
    required bool selected,
    required bool answered,
    required bool isCorrectOption,
    required bool isChosenOption,
    required VoidCallback? onTap,
  }) {
    final theme = Theme.of(context);
    Color borderColor = Colors.white.withValues(alpha: 0.28);
    Color background = Colors.transparent;
    if (answered) {
      if (isCorrectOption) {
        borderColor = Colors.greenAccent;
        background = Colors.greenAccent.withValues(alpha: 0.18);
      } else if (isChosenOption) {
        borderColor = Colors.redAccent;
        background = Colors.redAccent.withValues(alpha: 0.18);
      }
    } else if (selected) {
      borderColor = theme.colorScheme.secondary;
      background = theme.colorScheme.secondary.withValues(alpha: 0.18);
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        onLongPress: () async {
          await Clipboard.setData(ClipboardData(text: text));
          if (!mounted) {
            return;
          }
          ScaffoldMessenger.of(this.context).showSnackBar(
            const SnackBar(content: Text('Текст ответа скопирован')),
          );
        },
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: borderColor,
              width: selected || answered ? 2 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('$optionNumber. $text', softWrap: true),
              if (text.trim().length > 120)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: () => _showFullTextDialog(
                      title: 'Полный вариант ответа',
                      text: text,
                    ),
                    child: const Text('Открыть полностью'),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showFullTextDialog({
    required String title,
    required String text,
  }) async {
    if (!mounted) {
      return;
    }
    final media = MediaQuery.of(context);
    final useFullscreen = media.size.width < 900;
    final scrollBody = Scrollbar(
      thumbVisibility: true,
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: SelectableText(text, style: const TextStyle(height: 1.45)),
      ),
    );

    if (useFullscreen) {
      await showDialog<void>(
        context: context,
        builder: (context) => Dialog.fullscreen(
          child: SafeArea(
            child: Column(
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          title,
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close),
                        tooltip: 'Закрыть',
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: scrollBody,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Закрыть'),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      return;
    }

    final dialogHeight = (media.size.height * 0.7)
        .clamp(300.0, 620.0)
        .toDouble();
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: SizedBox(width: 780, height: dialogHeight, child: scrollBody),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Закрыть'),
          ),
        ],
      ),
    );
  }

  String _questionPreview(String raw) {
    final text = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (text.length <= 80) {
      return text;
    }
    return '${text.substring(0, 80)}...';
  }

  Future<void> _showQuestionJumpDialog(
    BuildContext context,
    AppState appState,
  ) async {
    final session = appState.studySession;
    if (session == null || session.questions.isEmpty) {
      return;
    }
    var selectedIndex = session.currentIndex;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Перейти к вопросу'),
          content: SizedBox(
            width: 760,
            child: DropdownButtonFormField<int>(
              initialValue: selectedIndex,
              isExpanded: true,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Выберите вопрос',
              ),
              items: List<DropdownMenuItem<int>>.generate(
                session.questions.length,
                (index) {
                  final question = session.questions[index];
                  return DropdownMenuItem<int>(
                    value: index,
                    child: Text(
                      '${index + 1}. ${_questionPreview(question.questionText)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  );
                },
              ),
              onChanged: (value) {
                if (value == null) {
                  return;
                }
                setDialogState(() {
                  selectedIndex = value;
                });
              },
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Перейти'),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true || !mounted) {
      return;
    }
    appState.jumpToStudyQuestion(selectedIndex);
    setState(() {
      _syncLocalFromSession(appState.studySession);
    });
  }

  Widget _buildSubmitAnswerButton(AppState appState) {
    final session = appState.studySession;
    final answeredCurrent =
        session != null &&
        !session.isCompleted &&
        session.quizSelectedOptions.containsKey(session.currentIndex);
    return FilledButton(
      onPressed: answeredCurrent || _selectedOptions.isEmpty
          ? null
          : () async {
              await appState.answerQuizOptions(
                _selectedOptions.toList(growable: false),
              );
              if (!mounted) {
                return;
              }
              setState(() {
                _syncLocalFromSession(appState.studySession);
              });
            },
      child: const Text('Ответить'),
    );
  }

  void _handleMultiSelectInputChanged(String value, List<String> options) {
    if (_isSyncingMultiSelectInput) {
      return;
    }
    final parsedIndexes = RegExp(
      r'\d+',
    ).allMatches(value).map((match) => int.parse(match.group(0)!)).toSet();
    setState(() {
      _selectedOptions
        ..clear()
        ..addAll(
          parsedIndexes
              .where((index) => index >= 1 && index <= options.length)
              .map((index) => options[index - 1]),
        );
    });
  }

  void _syncMultiSelectInputValue(String value) {
    if (_multiSelectInputController.text == value) {
      return;
    }
    _isSyncingMultiSelectInput = true;
    _multiSelectInputController.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
    _isSyncingMultiSelectInput = false;
  }

  Future<void> _handleFullscreenMenuAction(
    _FullscreenMenuAction action,
    BuildContext context,
    AppState appState,
  ) async {
    switch (action) {
      case _FullscreenMenuAction.explain:
        final explanation = await appState.explainCurrentQuestion();
        if (!mounted) {
          return;
        }
        setState(() {
          _explanation = explanation;
        });
        return;
      case _FullscreenMenuAction.memoryTip:
        final tip = await appState.buildMemoryTipForCurrentQuestion();
        if (!mounted) {
          return;
        }
        setState(() {
          _memoryTip = tip;
        });
        return;
      case _FullscreenMenuAction.reset:
        await _confirmResetSession(context, appState);
        return;
      case _FullscreenMenuAction.exit:
        if (!mounted) {
          return;
        }
        Navigator.of(context).maybePop();
        return;
    }
  }

  void _syncLocalFromSession(StudySessionState? session) {
    if (session == null || session.isCompleted) {
      _selectedOptions.clear();
      _syncMultiSelectInputValue('');
      _explanation = null;
      _memoryTip = null;
      return;
    }
    final idx = session.currentIndex;
    final questionId = session.currentQuestion.id;
    _selectedOptions
      ..clear()
      ..addAll(
        context.read<AppState>().decodeSelectedAnswers(
          session.quizSelectedOptions[idx],
        ),
      );
    _explanation = questionId == null ? null : session.explanations[questionId];
    _memoryTip = questionId == null ? null : session.memoryTips[questionId];
  }

  Future<void> _confirmResetSession(
    BuildContext context,
    AppState appState,
  ) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Сбросить текущий тест?'),
        content: const Text(
          'Текущая сессия будет остановлена, и вы сможете выбрать новый тест.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Сбросить'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      _resetCurrentSession(appState);
    }
  }
}

class _QuizFullscreenPage extends StatelessWidget {
  const _QuizFullscreenPage();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0E1117),
      body: const SafeArea(
        child: SelectionArea(child: StudyScreen(immersiveMode: true)),
      ),
    );
  }
}
