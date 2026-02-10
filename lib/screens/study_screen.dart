import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/quiz_engine.dart';
import '../state/app_state.dart';

class StudyScreen extends StatefulWidget {
  const StudyScreen({super.key});

  @override
  State<StudyScreen> createState() => _StudyScreenState();
}

class _StudyScreenState extends State<StudyScreen> {
  StudyMode _mode = StudyMode.quiz;
  String _category = 'Все';
  int? _difficulty;
  int _questionCount = 20;
  int _availableQuestions = 0;
  bool _availableQuestionsLoading = false;
  bool _hasLoadedAvailableQuestions = false;
  bool _useAllQuestions = false;
  int _countRequestId = 0;

  final Map<String, List<String>> _optionsCache = <String, List<String>>{};
  String? _selectedOption;
  String? _explanation;

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
                Row(
                  children: <Widget>[
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _category,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          labelText: 'Категория',
                        ),
                        items: appState.categories
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
                            _useAllQuestions = false;
                          });
                          _refreshAvailableCount(appState);
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: DropdownButtonFormField<int?>(
                        initialValue: _difficulty,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          labelText: 'Сложность',
                        ),
                        items: const <DropdownMenuItem<int?>>[
                          DropdownMenuItem<int?>(
                            value: null,
                            child: Text('Все'),
                          ),
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
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
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
                          final error = await appState.startStudySession(
                            mode: _mode,
                            totalQuestions: targetCount,
                            category: _category,
                            difficulty: _difficulty,
                          );
                          if (!context.mounted) {
                            return;
                          }
                          if (error != null) {
                            ScaffoldMessenger.of(
                              context,
                            ).showSnackBar(SnackBar(content: Text(error)));
                          } else {
                            _selectedOption = null;
                            _optionsCache.clear();
                            _explanation = null;
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

  Widget _buildActiveSession(BuildContext context, AppState appState) {
    final session = appState.studySession!;
    final question = session.currentQuestion;
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
                  child: OutlinedButton.icon(
                    onPressed: () => _confirmResetSession(context, appState),
                    icon: const Icon(Icons.restart_alt),
                    label: const Text('Сбросить тест'),
                  ),
                ),
                LinearProgressIndicator(value: progress),
                const SizedBox(height: 8),
                Text(
                  'Вопрос ${session.currentIndex + 1} / ${session.questions.length}',
                  style: TextStyle(color: Colors.grey.shade300),
                ),
                const SizedBox(height: 6),
                Text(
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
                    if ((question.competency ?? '').trim().isNotEmpty)
                      Chip(label: Text(question.competency!)),
                    Chip(label: Text(question.category ?? 'Без категории')),
                    Chip(label: Text('Difficulty ${question.difficulty}')),
                  ],
                ),
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
    final cacheKey = '${question.id ?? session.currentIndex}';
    final options = _optionsCache.putIfAbsent(
      cacheKey,
      () => appState.quizEngine.buildOptions(
        question,
        fallbackPool: session.questions,
      ),
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            if (!session.answeredCurrent) ...<Widget>[
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: options
                    .map(
                      (option) => ChoiceChip(
                        selected: _selectedOption == option,
                        label: Text(option),
                        onSelected: (_) {
                          setState(() {
                            _selectedOption = option;
                          });
                        },
                      ),
                    )
                    .toList(growable: false),
              ),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: _selectedOption == null
                    ? null
                    : () async {
                        await appState.answerQuizOption(_selectedOption!);
                        if (!mounted) {
                          return;
                        }
                        setState(() {});
                      },
                child: const Text('Ответить'),
              ),
            ] else ...<Widget>[
              Text(
                session.lastIsCorrect ? '✅ Верно' : '❌ Неверно',
                style: TextStyle(
                  color: session.lastIsCorrect
                      ? Colors.greenAccent
                      : Colors.redAccent,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (!session.lastIsCorrect) ...<Widget>[
                const SizedBox(height: 6),
                Text('Правильный ответ: ${question.correctAnswer}'),
              ],
              const SizedBox(height: 4),
              Text('Время: ${session.lastTimeSeconds.toStringAsFixed(1)} сек'),
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
                  FilledButton(
                    onPressed: () {
                      setState(() {
                        _selectedOption = null;
                        _explanation = null;
                      });
                      appState.nextStudyQuestion();
                    },
                    child: const Text('Следующий'),
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
                  child: Text(_explanation!),
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
              Text(
                question.correctAnswer,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
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
                const SizedBox(height: 8),
                FilledButton(
                  onPressed: appState.nextStudyQuestion,
                  child: const Text('Следующая карточка'),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSessionSummary(BuildContext context, AppState appState) {
    final session = appState.studySession!;
    final accuracy = session.questions.isEmpty
        ? 0.0
        : (session.correctCount / session.questions.length) * 100;

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
                Text('Точность: ${accuracy.toStringAsFixed(1)}%'),
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
                  ],
                ),
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
      final count = await appState.countQuestionsForMode(
        mode: _mode,
        category: _category,
        difficulty: _difficulty,
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

  void _resetCurrentSession(AppState appState) {
    setState(() {
      _selectedOption = null;
      _explanation = null;
      _optionsCache.clear();
    });
    appState.stopSession();
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
