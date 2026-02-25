import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';

import '../models/question.dart';
import '../services/ai_progress.dart';
import '../services/competency_service.dart';
import '../services/database_service.dart';
import '../services/excel_parser_service.dart';
import '../services/openrouter_service.dart';
import '../services/quiz_engine.dart';
import '../services/web_search_service.dart';

class _BusyProgressMarker {
  const _BusyProgressMarker();
}

class UploadDuplicateGroup {
  const UploadDuplicateGroup({
    required this.questionText,
    required this.correctAnswer,
    required this.wrongAnswers,
    required this.count,
    required this.sources,
  });

  final String questionText;
  final String correctAnswer;
  final List<String> wrongAnswers;
  final int count;
  final List<String> sources;

  int get duplicatesOnly => count > 1 ? count - 1 : 0;
}

class UploadDatabaseStats {
  const UploadDatabaseStats({
    required this.totalRows,
    required this.uniqueRows,
    required this.duplicateRowsInUpload,
    required this.alreadyInDatabase,
    required this.similarByQuestionText,
    required this.answerMismatches,
    required this.pureNew,
    required this.newForDatabase,
  });

  final int totalRows;
  final int uniqueRows;
  final int duplicateRowsInUpload;
  final int alreadyInDatabase;
  final int similarByQuestionText;
  final int answerMismatches;
  final int pureNew;
  final int newForDatabase;
}

class UploadSimilarityMatch {
  const UploadSimilarityMatch({
    required this.incoming,
    required this.existing,
    required this.similarity,
    required this.answerMatches,
  });

  final Question incoming;
  final Question existing;
  final double similarity;
  final bool answerMatches;
}

enum AiProvider { openrouter, local }

extension AiProviderX on AiProvider {
  String get label {
    switch (this) {
      case AiProvider.openrouter:
        return 'OpenRouter';
      case AiProvider.local:
        return 'Local rules';
    }
  }
}

class StudySessionState {
  StudySessionState({
    required this.mode,
    required this.sessionId,
    required this.questions,
    this.currentIndex = 0,
    this.correctCount = 0,
    this.answeredCurrent = false,
    this.showAnswer = false,
    DateTime? startedAtCurrent,
    this.lastIsCorrect = false,
    this.lastTimeSeconds = 0,
    Map<int, String>? explanations,
    Map<int, String>? memoryTips,
    Map<int, String>? internetContexts,
    Map<int, String>? quizSelectedOptions,
    Map<int, bool>? quizIsCorrectByIndex,
    Map<int, double>? quizTimeSecondsByIndex,
    this.finalized = false,
  }) : startedAtCurrent = startedAtCurrent ?? DateTime.now(),
       explanations = explanations ?? <int, String>{},
       memoryTips = memoryTips ?? <int, String>{},
       internetContexts = internetContexts ?? <int, String>{},
       quizSelectedOptions = quizSelectedOptions ?? <int, String>{},
       quizIsCorrectByIndex = quizIsCorrectByIndex ?? <int, bool>{},
       quizTimeSecondsByIndex = quizTimeSecondsByIndex ?? <int, double>{};

  final StudyMode mode;
  final String sessionId;
  final List<Question> questions;
  int currentIndex;
  int correctCount;
  bool answeredCurrent;
  bool showAnswer;
  DateTime startedAtCurrent;
  bool lastIsCorrect;
  double lastTimeSeconds;
  final Map<int, String> explanations;
  final Map<int, String> memoryTips;
  final Map<int, String> internetContexts;
  final Map<int, String> quizSelectedOptions;
  final Map<int, bool> quizIsCorrectByIndex;
  final Map<int, double> quizTimeSecondsByIndex;
  bool finalized;

  bool get isCompleted => currentIndex >= questions.length;
  Question get currentQuestion => questions[currentIndex];
}

class AppState extends ChangeNotifier {
  static const _BusyProgressMarker _progressUnset = _BusyProgressMarker();

  AppState()
    : databaseService = DatabaseService.instance,
      excelParserService = ExcelParserService() {
    quizEngine = QuizEngine(databaseService: databaseService);
    openRouterService = OpenRouterService(
      databaseService: databaseService,
      apiKey: openRouterApiKey,
    );
    localOnlyService = OpenRouterService(
      databaseService: databaseService,
      apiKey: '',
    );
  }

  final DatabaseService databaseService;
  final ExcelParserService excelParserService;
  final CompetencyService competencyService = CompetencyService();
  final WebSearchService webSearchService = const WebSearchService();
  late final QuizEngine quizEngine;
  late OpenRouterService openRouterService;
  late OpenRouterService localOnlyService;

  bool initialized = false;
  bool busy = false;
  String busyTitle = '';
  String busyDetails = '';
  double? busyProgress;
  DateTime? _busyStartedAt;
  String? errorMessage;

  String openRouterApiKey = const String.fromEnvironment(
    'OPENROUTER_API_KEY',
    defaultValue: '',
  );
  String explanationPromptTemplate =
      OpenRouterService.defaultExplanationUserPromptTemplate;
  String memoryTipPromptTemplate =
      OpenRouterService.defaultMemoryTipUserPromptTemplate;
  bool aiUseInternetSearch = true;
  AiProvider aiProvider = AiProvider.openrouter;
  List<String> categories = <String>['Все'];
  final List<String> competencyCatalog = CompetencyService.allCompetencies;
  Map<String, Object> userStats = <String, Object>{};
  int dueReviewCount = 0;

  List<Question> uploadQuestions = <Question>[];
  List<String> uploadWarnings = <String>[];
  bool uploadCategorized = false;
  bool uploadSaved = false;
  int? lastSaveInputCount;
  int? lastSaveChangedCount;
  UploadDatabaseStats? uploadDatabaseStats;
  List<Question> uploadNewQuestions = <Question>[];
  List<UploadSimilarityMatch> uploadSimilarQuestions =
      <UploadSimilarityMatch>[];
  List<UploadSimilarityMatch> uploadAnswerMismatchQuestions =
      <UploadSimilarityMatch>[];

  StudySessionState? studySession;

  Future<void> initialize() async {
    if (initialized) {
      return;
    }
    await databaseService.database;
    await _loadAiPromptSettings();
    await refreshDashboard();
    initialized = true;
    notifyListeners();
  }

  Future<void> updateAiSettings({
    required AiProvider provider,
    required String openRouterKey,
    required String explanationPrompt,
    required String memoryTipPrompt,
    required bool useInternetSearch,
  }) async {
    aiProvider = provider;
    openRouterApiKey = openRouterKey.trim();
    explanationPromptTemplate = explanationPrompt.trim().isEmpty
        ? OpenRouterService.defaultExplanationUserPromptTemplate
        : explanationPrompt.trim();
    memoryTipPromptTemplate = memoryTipPrompt.trim().isEmpty
        ? OpenRouterService.defaultMemoryTipUserPromptTemplate
        : memoryTipPrompt.trim();
    aiUseInternetSearch = useInternetSearch;

    openRouterService = OpenRouterService(
      databaseService: databaseService,
      apiKey: openRouterApiKey,
    );
    localOnlyService = OpenRouterService(
      databaseService: databaseService,
      apiKey: '',
    );
    studySession?.explanations.clear();
    studySession?.memoryTips.clear();
    studySession?.internetContexts.clear();
    final payload = jsonEncode(<String, String>{
      'explanation_prompt': explanationPromptTemplate,
      'memory_tip_prompt': memoryTipPromptTemplate,
      'use_internet_search': aiUseInternetSearch ? '1' : '0',
    });
    await databaseService.setCache(
      cacheKey: 'settings:ai_prompts',
      cacheType: 'settings',
      payload: payload,
    );
    notifyListeners();
  }

  Future<void> _loadAiPromptSettings() async {
    final payload = await databaseService.getCache('settings:ai_prompts');
    if (payload == null || payload.trim().isEmpty) {
      return;
    }
    try {
      final decoded = jsonDecode(payload);
      if (decoded is! Map) {
        return;
      }
      final explanation = (decoded['explanation_prompt'] ?? '')
          .toString()
          .trim();
      final memory = (decoded['memory_tip_prompt'] ?? '').toString().trim();
      final useInternetSearch = (decoded['use_internet_search'] ?? '1')
          .toString()
          .trim();
      if (explanation.isNotEmpty) {
        explanationPromptTemplate = explanation;
      }
      if (memory.isNotEmpty) {
        memoryTipPromptTemplate = memory;
      }
      aiUseInternetSearch = useInternetSearch != '0';
    } catch (_) {}
  }

  Future<void> refreshDashboard() async {
    userStats = await databaseService.getUserStatistics();
    final dbCategories = await databaseService.getCategories();
    categories = <String>['Все', ...dbCategories];
    dueReviewCount = await databaseService.dueReviewCount();
    notifyListeners();
  }

  Future<int> countQuestionsForMode({
    required StudyMode mode,
    String? category,
    int? difficulty,
  }) async {
    switch (mode) {
      case StudyMode.review:
        return databaseService.dueReviewCount();
      case StudyMode.quiz:
      case StudyMode.flashcards:
      case StudyMode.categoryDrill:
      case StudyMode.weakSpots:
        return databaseService.countQuestions(
          category: category,
          difficulty: difficulty,
        );
      case StudyMode.hardQuestions:
        return databaseService.countQuestions(
          category: category,
          difficulty: difficulty,
          onlyHard: true,
        );
    }
  }

  void _setBusyState({
    required bool value,
    String? title,
    String? details,
    Object? progress = _progressUnset,
    bool resetTimer = false,
  }) {
    busy = value;
    if (value) {
      if (title != null) {
        busyTitle = title;
      }
      if (details != null) {
        busyDetails = details;
      }
      if (progress is! _BusyProgressMarker) {
        busyProgress = progress as double?;
      }
      if (resetTimer || _busyStartedAt == null) {
        _busyStartedAt = DateTime.now();
      }
    } else {
      busyTitle = '';
      busyDetails = '';
      busyProgress = null;
      _busyStartedAt = null;
    }
    notifyListeners();
  }

  String _formatEta(Duration duration) {
    final totalSeconds = duration.inSeconds;
    if (totalSeconds <= 0) {
      return '0с';
    }
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;
    if (hours > 0) {
      return '$hoursч $minutesм';
    }
    if (minutes > 0) {
      return '$minutesм $secondsс';
    }
    return '$secondsс';
  }

  Question _withResolvedCompetency(Question question) {
    final resolved = competencyService.resolveCompetency(
      rawCompetency: question.competency,
      questionText: question.questionText,
      category: question.category,
      subcategory: question.subcategory,
    );
    final normalizedCategory = (question.category ?? '').trim().isEmpty
        ? resolved
        : question.category;
    return question.copyWith(
      competency: resolved,
      category: normalizedCategory,
    );
  }

  List<Question> _normalizeUploadCompetencies(List<Question> questions) {
    return questions.map(_withResolvedCompetency).toList(growable: false);
  }

  String _normalizeForDuplicate(String value) {
    return value.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  String _normalizeForComparison(String value) {
    final lowered = value.toLowerCase().trim();
    final cleaned = lowered.replaceAll(
      RegExp(r'[^a-zа-я0-9 ]', unicode: true),
      ' ',
    );
    return cleaned.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  Set<String> _tokenizeForComparison(String value) {
    final normalized = _normalizeForComparison(value);
    if (normalized.isEmpty) {
      return <String>{};
    }
    return normalized.split(' ').where((token) => token.length >= 2).toSet();
  }

  double _jaccardSimilarity(Set<String> a, Set<String> b) {
    if (a.isEmpty || b.isEmpty) {
      return 0.0;
    }
    final intersection = a.intersection(b).length.toDouble();
    if (intersection == 0) {
      return 0.0;
    }
    final union = a.union(b).length.toDouble();
    if (union == 0) {
      return 0.0;
    }
    return intersection / union;
  }

  String _buildDuplicateKey(Question question) {
    final wrong = List<String>.from(question.wrongAnswers);
    while (wrong.length < 3) {
      wrong.add('');
    }
    return <String>[
      _normalizeForDuplicate(question.questionText),
      _normalizeForDuplicate(question.correctAnswer),
      _normalizeForDuplicate(wrong[0]),
      _normalizeForDuplicate(wrong[1]),
      _normalizeForDuplicate(wrong[2]),
    ].join('||');
  }

  List<UploadDuplicateGroup> get uploadDuplicateGroups {
    if (uploadQuestions.isEmpty) {
      return const <UploadDuplicateGroup>[];
    }
    final buckets = <String, List<Question>>{};
    for (final question in uploadQuestions) {
      final key = _buildDuplicateKey(question);
      buckets.putIfAbsent(key, () => <Question>[]).add(question);
    }

    final groups = <UploadDuplicateGroup>[];
    for (final bucket in buckets.values) {
      if (bucket.length < 2) {
        continue;
      }
      final first = bucket.first;
      final sources = bucket
          .map((q) {
            final source = q.sourceFile?.trim() ?? '';
            return source.isEmpty ? 'неизвестный источник' : source;
          })
          .toSet()
          .toList(growable: false);
      groups.add(
        UploadDuplicateGroup(
          questionText: first.questionText,
          correctAnswer: first.correctAnswer,
          wrongAnswers: List<String>.from(first.wrongAnswers),
          count: bucket.length,
          sources: sources,
        ),
      );
    }
    groups.sort((a, b) {
      final byCount = b.count.compareTo(a.count);
      if (byCount != 0) {
        return byCount;
      }
      return a.questionText.compareTo(b.questionText);
    });
    return groups;
  }

  int get uploadDuplicateRows {
    return uploadDuplicateGroups.fold<int>(
      0,
      (sum, group) => sum + group.duplicatesOnly,
    );
  }

  Future<void> _rebuildUploadDatabaseStats({
    required bool resetBusyState,
  }) async {
    if (uploadQuestions.isEmpty) {
      uploadDatabaseStats = null;
      uploadNewQuestions = <Question>[];
      uploadSimilarQuestions = <UploadSimilarityMatch>[];
      uploadAnswerMismatchQuestions = <UploadSimilarityMatch>[];
      notifyListeners();
      return;
    }

    if (resetBusyState) {
      _setBusyState(
        value: true,
        title: 'Сверка с БД',
        details: 'Подготовка вопросов',
        progress: 0.0,
        resetTimer: true,
      );
    } else {
      _setBusyState(
        value: true,
        title: 'Сверка с БД',
        details: 'Подготовка вопросов',
        progress: 0.0,
      );
    }

    final uniqueByKey = <String, Question>{};
    for (final question in uploadQuestions) {
      final key = _buildDuplicateKey(question);
      uniqueByKey.putIfAbsent(key, () => question);
    }

    _setBusyState(
      value: true,
      title: 'Сверка с БД',
      details: 'Чтение базы вопросов',
      progress: 0.1,
    );

    final dbKeys = await databaseService.getNormalizedQuestionKeys(
      onProgress: (processed, total) {
        final ratio = total == 0 ? 1.0 : (processed / total).clamp(0.0, 1.0);
        _setBusyState(
          value: true,
          title: 'Сверка с БД',
          details: 'Сканирование БД: $processed/$total',
          progress: (0.1 + ratio * 0.8).clamp(0.0, 1.0),
        );
      },
    );

    var alreadyInDatabase = 0;
    final candidatesForSimilarity = <Question>[];
    for (final entry in uniqueByKey.entries) {
      if (dbKeys.contains(entry.key)) {
        alreadyInDatabase += 1;
      } else {
        candidatesForSimilarity.add(entry.value);
      }
    }

    _setBusyState(
      value: true,
      title: 'Сверка с БД',
      details: 'Подготовка похожих вопросов',
      progress: 0.92,
    );

    final dbPool = await databaseService.getQuestions(limit: 50000);
    final dbTokenSets = <Set<String>>[];
    final tokenToDbIndexes = <String, Set<int>>{};
    for (var i = 0; i < dbPool.length; i++) {
      final tokens = _tokenizeForComparison(dbPool[i].questionText);
      dbTokenSets.add(tokens);
      for (final token in tokens) {
        tokenToDbIndexes.putIfAbsent(token, () => <int>{}).add(i);
      }
    }

    const threshold = 0.60;
    final similarMatches = <UploadSimilarityMatch>[];
    final mismatchMatches = <UploadSimilarityMatch>[];
    final pureNewQuestions = <Question>[];

    final totalCandidates = candidatesForSimilarity.length;
    for (var i = 0; i < totalCandidates; i++) {
      final incoming = candidatesForSimilarity[i];
      final incomingTokens = _tokenizeForComparison(incoming.questionText);

      final candidateIndexes = <int>{};
      for (final token in incomingTokens) {
        final idxs = tokenToDbIndexes[token];
        if (idxs != null) {
          candidateIndexes.addAll(idxs);
        }
      }

      double bestScore = 0.0;
      Question? bestQuestion;
      for (final dbIndex in candidateIndexes) {
        final score = _jaccardSimilarity(incomingTokens, dbTokenSets[dbIndex]);
        if (score > bestScore) {
          bestScore = score;
          bestQuestion = dbPool[dbIndex];
        }
      }

      if (bestQuestion != null && bestScore >= threshold) {
        final sameAnswer =
            _normalizeForComparison(incoming.correctAnswer) ==
            _normalizeForComparison(bestQuestion.correctAnswer);
        final match = UploadSimilarityMatch(
          incoming: incoming,
          existing: bestQuestion,
          similarity: bestScore,
          answerMatches: sameAnswer,
        );
        if (sameAnswer) {
          similarMatches.add(match);
        } else {
          mismatchMatches.add(match);
        }
      } else {
        pureNewQuestions.add(incoming);
      }

      if ((i + 1) % 20 == 0 || i + 1 == totalCandidates) {
        final ratio = totalCandidates == 0
            ? 1.0
            : ((i + 1) / totalCandidates).clamp(0.0, 1.0);
        _setBusyState(
          value: true,
          title: 'Сверка с БД',
          details: 'Поиск похожих: ${i + 1}/$totalCandidates',
          progress: (0.92 + ratio * 0.08).clamp(0.0, 1.0),
        );
      }
    }

    uploadDatabaseStats = UploadDatabaseStats(
      totalRows: uploadQuestions.length,
      uniqueRows: uniqueByKey.length,
      duplicateRowsInUpload: uploadQuestions.length - uniqueByKey.length,
      alreadyInDatabase: alreadyInDatabase,
      similarByQuestionText: similarMatches.length,
      answerMismatches: mismatchMatches.length,
      pureNew: pureNewQuestions.length,
      newForDatabase: candidatesForSimilarity.length,
    );
    uploadNewQuestions = pureNewQuestions;
    uploadSimilarQuestions = similarMatches;
    uploadAnswerMismatchQuestions = mismatchMatches;
    notifyListeners();
  }

  Future<void> analyzeUploadAgainstDatabase() async {
    if (uploadQuestions.isEmpty) {
      return;
    }
    errorMessage = null;
    try {
      await _rebuildUploadDatabaseStats(resetBusyState: true);
    } catch (e) {
      errorMessage = 'Ошибка сверки с базой: $e';
    } finally {
      _setBusyState(value: false);
    }
  }

  Future<void> parseFiles(List<PlatformFile> files) async {
    _setBusyState(
      value: true,
      title: 'Парсинг Excel',
      details: files.isEmpty
          ? 'Нет выбранных файлов'
          : 'Файл 0/${files.length}',
      progress: files.isEmpty ? null : 0.0,
      resetTimer: true,
    );
    errorMessage = null;
    uploadDatabaseStats = null;
    uploadNewQuestions = <Question>[];
    uploadSimilarQuestions = <UploadSimilarityMatch>[];
    uploadAnswerMismatchQuestions = <UploadSimilarityMatch>[];

    try {
      final parsed = <Question>[];
      final warnings = <String>[];
      for (var index = 0; index < files.length; index++) {
        final file = files[index];
        _setBusyState(
          value: true,
          title: 'Парсинг Excel',
          details: 'Файл ${index + 1}/${files.length}: ${file.name}',
          progress: files.isEmpty ? null : (index / files.length),
        );

        final bytes = file.bytes;
        if (bytes == null) {
          warnings.add('Файл ${file.name} пропущен: нет байтов в памяти.');
          continue;
        }
        final result = await excelParserService.parse(
          bytes: bytes,
          sourceFile: file.name,
        );
        parsed.addAll(result.questions);
        warnings.addAll(result.warnings);

        _setBusyState(
          value: true,
          title: 'Парсинг Excel',
          details: 'Файл ${index + 1}/${files.length}: готово',
          progress: files.isEmpty ? null : ((index + 1) / files.length),
        );
      }
      uploadQuestions = _normalizeUploadCompetencies(parsed);
      uploadWarnings = warnings;
      uploadCategorized = false;
      uploadSaved = false;
      lastSaveInputCount = null;
      lastSaveChangedCount = null;
      await _rebuildUploadDatabaseStats(resetBusyState: false);
    } catch (e) {
      errorMessage = 'Ошибка парсинга файлов: $e';
    } finally {
      _setBusyState(value: false);
    }
  }

  Future<void> categorizeUploadedQuestions() async {
    if (uploadQuestions.isEmpty) {
      return;
    }
    final providerLabel = aiProvider.label;
    final totalQuestions = uploadQuestions.length;
    _setBusyState(
      value: true,
      title: 'Категоризация: $providerLabel',
      details: 'Подготовка ($totalQuestions вопросов)',
      progress: 0.0,
      resetTimer: true,
    );
    errorMessage = null;

    if (aiProvider == AiProvider.openrouter &&
        openRouterApiKey.trim().isEmpty) {
      uploadWarnings = <String>[
        ...uploadWarnings,
        'OpenRouter API key не задан. Используются локальные правила категоризации.',
      ];
    }

    try {
      switch (aiProvider) {
        case AiProvider.openrouter:
          uploadQuestions = await openRouterService.categorizeQuestions(
            uploadQuestions,
            onProgress: _onCategorizationProgress,
          );
          break;
        case AiProvider.local:
          uploadQuestions = await localOnlyService.categorizeQuestions(
            uploadQuestions,
            onProgress: _onCategorizationProgress,
          );
          break;
      }
      uploadQuestions = _normalizeUploadCompetencies(uploadQuestions);
      uploadCategorized = true;
    } catch (e) {
      errorMessage = 'Ошибка категоризации: $e';
    } finally {
      _setBusyState(value: false);
    }
  }

  void _onCategorizationProgress(CategorizationProgress progress) {
    final done = progress.processedQuestions;
    final total = progress.totalQuestions;
    var stagedDone = done.toDouble();
    final stageProgress = progress.stageProgress;
    final batchSize = progress.currentBatchSize ?? 0;
    if (stageProgress != null && batchSize > 0 && done < total) {
      final inBatch = (stageProgress.clamp(0.0, 1.0) * batchSize);
      stagedDone = (done + inBatch).clamp(0, total).toDouble();
    }
    final ratio = total == 0 ? 0.0 : (stagedDone / total).clamp(0.0, 1.0);

    var detail = '${progress.stage} · $done/$total';
    final started = _busyStartedAt;
    if (started != null) {
      final elapsed = DateTime.now().difference(started);
      detail = '$detail · Время ${_formatEta(elapsed)}';
    }
    if (started != null && done > 0 && done < total) {
      final elapsed = DateTime.now().difference(started);
      final remainingItems = total - stagedDone.round();
      final avgPerItemMs = elapsed.inMilliseconds / done;
      final eta = Duration(
        milliseconds: (avgPerItemMs * remainingItems).round(),
      );
      detail = '$detail · ETA ${_formatEta(eta)}';
    } else if (done == 0 && progress.stage.contains('запрос к OpenRouter')) {
      detail = '$detail · Первый батч может занять 20-40 сек';
    }

    _setBusyState(
      value: true,
      title: 'Категоризация: ${aiProvider.label}',
      details: detail,
      progress: ratio,
    );
  }

  Future<int> saveUploadedQuestions() async {
    if (uploadQuestions.isEmpty) {
      return 0;
    }
    _setBusyState(
      value: true,
      title: 'Сохранение в базу',
      details: 'Подготовка записи',
      progress: 0.0,
      resetTimer: true,
    );
    errorMessage = null;
    try {
      uploadQuestions = _normalizeUploadCompetencies(uploadQuestions);
      final inputCount = uploadQuestions.length;
      final inserted = await databaseService.addQuestions(
        uploadQuestions,
        onProgress: (progress) {
          final total = progress.total;
          final done = progress.processed;
          final ratio = total == 0 ? 1.0 : (done / total).clamp(0.0, 1.0);
          var details =
              'Запись: $done/$total · сохранено/обновлено: ${progress.changed}';
          final started = _busyStartedAt;
          if (started != null && done > 0 && done < total) {
            final elapsed = DateTime.now().difference(started);
            final remainingItems = total - done;
            final avgPerItemMs = elapsed.inMilliseconds / done;
            final eta = Duration(
              milliseconds: (avgPerItemMs * remainingItems).round(),
            );
            details = '$details · ETA ${_formatEta(eta)}';
          }
          _setBusyState(
            value: true,
            title: 'Сохранение в базу',
            details: details,
            progress: ratio,
          );
        },
      );
      uploadSaved = true;
      lastSaveInputCount = inputCount;
      lastSaveChangedCount = inserted;
      await refreshDashboard();
      return inserted;
    } catch (e) {
      errorMessage = 'Ошибка сохранения в базу: $e';
      return 0;
    } finally {
      _setBusyState(value: false);
    }
  }

  Future<int> fillMissingCompetenciesInDatabase() async {
    _setBusyState(
      value: true,
      title: 'Компетенции',
      details: 'Поиск вопросов без компетенции',
      progress: 0.0,
      resetTimer: true,
    );
    errorMessage = null;
    var updated = 0;

    try {
      final missing = await databaseService.getQuestionsWithoutCompetency(
        limit: 50000,
      );
      if (missing.isEmpty) {
        _setBusyState(
          value: true,
          title: 'Компетенции',
          details: 'Пустых компетенций не найдено',
          progress: 1.0,
        );
        await Future<void>.delayed(const Duration(milliseconds: 250));
        return 0;
      }

      for (var i = 0; i < missing.length; i++) {
        final question = missing[i];
        if (question.id == null) {
          continue;
        }
        final competency = competencyService.resolveCompetency(
          rawCompetency: question.competency,
          questionText: question.questionText,
          category: question.category,
          subcategory: question.subcategory,
        );
        await databaseService.updateQuestionCompetency(
          questionId: question.id!,
          competency: competency,
        );
        updated += 1;

        if (i % 25 == 0 || i == missing.length - 1) {
          _setBusyState(
            value: true,
            title: 'Компетенции',
            details: 'Заполнение: ${i + 1}/${missing.length}',
            progress: (i + 1) / missing.length,
          );
        }
      }
      await refreshDashboard();
      return updated;
    } catch (e) {
      errorMessage = 'Ошибка заполнения компетенций: $e';
      return 0;
    } finally {
      _setBusyState(value: false);
    }
  }

  void clearUploadState() {
    uploadQuestions = <Question>[];
    uploadWarnings = <String>[];
    uploadCategorized = false;
    uploadSaved = false;
    lastSaveInputCount = null;
    lastSaveChangedCount = null;
    uploadDatabaseStats = null;
    uploadNewQuestions = <Question>[];
    uploadSimilarQuestions = <UploadSimilarityMatch>[];
    uploadAnswerMismatchQuestions = <UploadSimilarityMatch>[];
    notifyListeners();
  }

  Future<void> resetDatabase() async {
    _setBusyState(
      value: true,
      title: 'Сброс базы',
      details: 'Удаление всех данных',
      progress: null,
      resetTimer: true,
    );
    errorMessage = null;
    try {
      await databaseService.clearAllData();
      uploadQuestions = <Question>[];
      uploadWarnings = <String>[];
      uploadCategorized = false;
      uploadSaved = false;
      lastSaveInputCount = null;
      lastSaveChangedCount = null;
      uploadDatabaseStats = null;
      uploadNewQuestions = <Question>[];
      uploadSimilarQuestions = <UploadSimilarityMatch>[];
      uploadAnswerMismatchQuestions = <UploadSimilarityMatch>[];
      studySession = null;
      await refreshDashboard();
    } catch (e) {
      errorMessage = 'Ошибка сброса базы: $e';
    } finally {
      _setBusyState(value: false);
    }
  }

  Future<String?> startStudySession({
    required StudyMode mode,
    required int totalQuestions,
    String? category,
    int? difficulty,
  }) async {
    _setBusyState(
      value: true,
      title: 'Подготовка сессии',
      details: 'Загрузка вопросов',
      progress: null,
      resetTimer: true,
    );
    errorMessage = null;
    try {
      final questions = await quizEngine.loadQuestionsForMode(
        mode: mode,
        limit: totalQuestions,
        category: category,
        difficulty: difficulty,
      );
      if (questions.isEmpty) {
        return 'Не найдено вопросов под выбранные фильтры.';
      }
      final sessionId = await quizEngine.startSession(
        mode: mode,
        totalQuestions: questions.length,
        categoryFilter: category,
      );
      studySession = StudySessionState(
        mode: mode,
        sessionId: sessionId,
        questions: questions,
      );
      return null;
    } catch (e) {
      return 'Ошибка запуска сессии: $e';
    } finally {
      _setBusyState(value: false);
    }
  }

  Future<void> answerQuizOption(String selectedOption) async {
    final session = studySession;
    if (session == null || session.isCompleted) {
      return;
    }
    final currentIndex = session.currentIndex;
    if (session.quizSelectedOptions.containsKey(currentIndex)) {
      session.answeredCurrent = true;
      notifyListeners();
      return;
    }
    final question = session.currentQuestion;
    final isCorrect = selectedOption == question.correctAnswer;
    final elapsed = DateTime.now().difference(session.startedAtCurrent);
    final timeSpentSeconds = elapsed.inMilliseconds / 1000.0;
    final quality = quizEngine.qualityFromQuiz(
      isCorrect: isCorrect,
      timeSpentSeconds: timeSpentSeconds,
    );

    await quizEngine.recordAnswer(
      question: question,
      userAnswer: selectedOption,
      isCorrect: isCorrect,
      timeSpentSeconds: timeSpentSeconds,
      sessionId: session.sessionId,
      quality: quality,
    );

    session.quizSelectedOptions[currentIndex] = selectedOption;
    session.quizIsCorrectByIndex[currentIndex] = isCorrect;
    session.quizTimeSecondsByIndex[currentIndex] = timeSpentSeconds;
    session.answeredCurrent = true;
    session.lastIsCorrect = isCorrect;
    session.lastTimeSeconds = timeSpentSeconds;
    if (isCorrect) {
      session.correctCount += 1;
    }
    notifyListeners();
  }

  Future<void> answerFlashcardLabel(String label) async {
    final session = studySession;
    if (session == null || session.isCompleted || session.answeredCurrent) {
      return;
    }
    final question = session.currentQuestion;
    final quality = quizEngine.qualityFromFlashcardLabel(label);
    final isCorrect = quality >= 3;
    final elapsed = DateTime.now().difference(session.startedAtCurrent);
    final timeSpentSeconds = elapsed.inMilliseconds / 1000.0;

    await quizEngine.recordAnswer(
      question: question,
      userAnswer: label,
      isCorrect: isCorrect,
      timeSpentSeconds: timeSpentSeconds,
      sessionId: session.sessionId,
      quality: quality,
    );

    session.answeredCurrent = true;
    session.lastIsCorrect = isCorrect;
    session.lastTimeSeconds = timeSpentSeconds;
    if (isCorrect) {
      session.correctCount += 1;
    }
    notifyListeners();
  }

  void revealFlashcardAnswer() {
    final session = studySession;
    if (session == null || session.isCompleted) {
      return;
    }
    session.showAnswer = true;
    notifyListeners();
  }

  void nextStudyQuestion() {
    final session = studySession;
    if (session == null) {
      return;
    }
    session.currentIndex += 1;
    _syncCurrentQuestionFlags(session);
    session.showAnswer = session.answeredCurrent;
    if (!session.answeredCurrent) {
      session.showAnswer = false;
    }
    notifyListeners();
  }

  void previousStudyQuestion() {
    final session = studySession;
    if (session == null || session.currentIndex <= 0) {
      return;
    }
    session.currentIndex -= 1;
    _syncCurrentQuestionFlags(session);
    session.showAnswer = session.answeredCurrent;
    notifyListeners();
  }

  void jumpToStudyQuestion(int index) {
    final session = studySession;
    if (session == null || session.questions.isEmpty) {
      return;
    }
    final bounded = index.clamp(0, session.questions.length - 1);
    if (bounded == session.currentIndex) {
      return;
    }
    session.currentIndex = bounded;
    _syncCurrentQuestionFlags(session);
    session.showAnswer = session.answeredCurrent;
    if (!session.answeredCurrent) {
      session.showAnswer = false;
    }
    notifyListeners();
  }

  void _syncCurrentQuestionFlags(StudySessionState session) {
    if (session.isCompleted) {
      session.answeredCurrent = false;
      session.lastIsCorrect = false;
      session.lastTimeSeconds = 0;
      return;
    }
    final idx = session.currentIndex;
    final selected = session.quizSelectedOptions[idx];
    if (selected == null) {
      session.answeredCurrent = false;
      session.lastIsCorrect = false;
      session.lastTimeSeconds = 0;
      session.startedAtCurrent = DateTime.now();
      return;
    }
    session.answeredCurrent = true;
    session.lastIsCorrect = session.quizIsCorrectByIndex[idx] ?? false;
    session.lastTimeSeconds = session.quizTimeSecondsByIndex[idx] ?? 0;
  }

  Future<void> finalizeSessionIfNeeded() async {
    final session = studySession;
    if (session == null || !session.isCompleted || session.finalized) {
      return;
    }
    session.finalized = true;
    await quizEngine.finishSession(
      sessionId: session.sessionId,
      totalQuestions: session.questions.length,
      correctAnswers: session.correctCount,
    );
    await refreshDashboard();
    notifyListeners();
  }

  Future<String> explainCurrentQuestion() async {
    final session = studySession;
    if (session == null || session.isCompleted) {
      return '';
    }
    final question = session.currentQuestion;
    if (question.id == null) {
      return 'Вопрос ещё не сохранён в базу.';
    }
    final existing = session.explanations[question.id!];
    if (existing != null && existing.trim().isNotEmpty) {
      return existing;
    }
    late final String explanation;
    final internetContext = await _resolveInternetContext(
      session: session,
      question: question,
    );
    switch (aiProvider) {
      case AiProvider.openrouter:
        explanation = await openRouterService.generateExplanation(
          questionId: question.id!,
          question: question.questionText,
          correctAnswer: question.correctAnswer,
          userPromptTemplate: explanationPromptTemplate,
          internetContext: internetContext,
        );
        break;
      case AiProvider.local:
        explanation = await localOnlyService.generateExplanation(
          questionId: question.id!,
          question: question.questionText,
          correctAnswer: question.correctAnswer,
          userPromptTemplate: explanationPromptTemplate,
          internetContext: internetContext,
        );
        break;
    }
    session.explanations[question.id!] = explanation;
    notifyListeners();
    return explanation;
  }

  Future<String> buildMemoryTipForCurrentQuestion() async {
    final session = studySession;
    if (session == null || session.isCompleted) {
      return '';
    }
    final question = session.currentQuestion;
    if (question.id == null) {
      return 'Вопрос ещё не сохранён в базу.';
    }
    final existing = session.memoryTips[question.id!];
    if (existing != null && existing.trim().isNotEmpty) {
      return existing;
    }
    late final String memoryTip;
    final internetContext = await _resolveInternetContext(
      session: session,
      question: question,
    );
    switch (aiProvider) {
      case AiProvider.openrouter:
        memoryTip = await openRouterService.generateMemoryTip(
          questionId: question.id!,
          question: question.questionText,
          correctAnswer: question.correctAnswer,
          userPromptTemplate: memoryTipPromptTemplate,
          internetContext: internetContext,
        );
        break;
      case AiProvider.local:
        memoryTip = await localOnlyService.generateMemoryTip(
          questionId: question.id!,
          question: question.questionText,
          correctAnswer: question.correctAnswer,
          userPromptTemplate: memoryTipPromptTemplate,
          internetContext: internetContext,
        );
        break;
    }
    session.memoryTips[question.id!] = memoryTip;
    notifyListeners();
    return memoryTip;
  }

  Future<String> _resolveInternetContext({
    required StudySessionState session,
    required Question question,
  }) async {
    if (!aiUseInternetSearch) {
      return '';
    }
    final questionId = question.id;
    if (questionId == null) {
      return '';
    }
    final cached = session.internetContexts[questionId];
    if (cached != null) {
      return cached;
    }

    final query = <String>[
      question.questionText.trim(),
      question.correctAnswer.trim(),
      (question.category ?? '').trim(),
    ].where((item) => item.isNotEmpty).join(' ');

    final results = await webSearchService.search(query, limit: 5);
    final contextBlock = webSearchService.buildContextBlock(results);
    session.internetContexts[questionId] = contextBlock;
    return contextBlock;
  }

  Future<bool?> toggleCurrentQuestionHard() async {
    final session = studySession;
    if (session == null || session.isCompleted) {
      return null;
    }
    final current = session.currentQuestion;
    final questionId = current.id;
    if (questionId == null) {
      return null;
    }
    final nextValue = !current.isHard;
    await databaseService.setQuestionHardStatus(
      questionId: questionId,
      isHard: nextValue,
    );
    session.questions[session.currentIndex] = current.copyWith(
      isHard: nextValue,
    );
    notifyListeners();
    return nextValue;
  }

  Future<String> generateStudyPlan() async {
    final weak = await databaseService.weakestCategories(limit: 5);
    final payload = <String, Object>{...userStats, 'weakest_categories': weak};
    switch (aiProvider) {
      case AiProvider.openrouter:
        return openRouterService.suggestStudyPlan(payload);
      case AiProvider.local:
        return localOnlyService.suggestStudyPlan(payload);
    }
  }

  void stopSession() {
    studySession = null;
    notifyListeners();
  }

  Future<List<Question>> loadLibrary({
    String? category,
    int? difficulty,
    String? searchQuery,
    bool onlyHard = false,
  }) {
    return databaseService.getQuestions(
      category: category,
      difficulty: difficulty,
      searchQuery: searchQuery,
      onlyHard: onlyHard,
      limit: 5000,
    );
  }

  Future<void> setQuestionHardStatus({
    required int questionId,
    required bool isHard,
  }) async {
    await databaseService.setQuestionHardStatus(
      questionId: questionId,
      isHard: isHard,
    );
  }

  Future<void> updateQuestionCategory({
    required int questionId,
    required String category,
    String? competency,
    String? subcategory,
    int? difficulty,
  }) async {
    await databaseService.updateQuestionCategory(
      questionId: questionId,
      category: category,
      competency: competency,
      subcategory: subcategory,
      difficulty: difficulty,
    );
    await refreshDashboard();
  }

  Future<void> deleteQuestion(int questionId) async {
    await databaseService.deleteQuestion(questionId);
    await refreshDashboard();
  }

  Future<List<Map<String, Object?>>> categoryStats() {
    return databaseService.getCategoryStatistics();
  }

  Future<List<Map<String, Object?>>> progressByDay() {
    return databaseService.getProgressByDay(days: 90);
  }

  Future<List<double>> responseTimes() {
    return databaseService.getResponseTimeDistribution();
  }
}
