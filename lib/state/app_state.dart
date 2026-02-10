import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';

import '../models/question.dart';
import '../services/ai_progress.dart';
import '../services/competency_service.dart';
import '../services/database_service.dart';
import '../services/excel_parser_service.dart';
import '../services/openrouter_service.dart';
import '../services/quiz_engine.dart';

class _BusyProgressMarker {
  const _BusyProgressMarker();
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
    this.finalized = false,
  }) : startedAtCurrent = startedAtCurrent ?? DateTime.now(),
       explanations = explanations ?? <int, String>{};

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
  AiProvider aiProvider = AiProvider.openrouter;
  List<String> categories = <String>['Все'];
  final List<String> competencyCatalog = CompetencyService.allCompetencies;
  Map<String, Object> userStats = <String, Object>{};
  int dueReviewCount = 0;

  List<Question> uploadQuestions = <Question>[];
  List<String> uploadWarnings = <String>[];
  bool uploadCategorized = false;
  bool uploadSaved = false;

  StudySessionState? studySession;

  Future<void> initialize() async {
    if (initialized) {
      return;
    }
    await databaseService.database;
    await refreshDashboard();
    initialized = true;
    notifyListeners();
  }

  void updateAiSettings({
    required AiProvider provider,
    required String openRouterKey,
  }) {
    aiProvider = provider;
    openRouterApiKey = openRouterKey.trim();

    openRouterService = OpenRouterService(
      databaseService: databaseService,
      apiKey: openRouterApiKey,
    );
    localOnlyService = OpenRouterService(
      databaseService: databaseService,
      apiKey: '',
    );
    studySession?.explanations.clear();
    notifyListeners();
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
      details: 'Запись вопросов в SQLite',
      progress: null,
      resetTimer: true,
    );
    errorMessage = null;
    try {
      uploadQuestions = _normalizeUploadCompetencies(uploadQuestions);
      final inserted = await databaseService.addQuestions(uploadQuestions);
      uploadSaved = true;
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
    if (session == null || session.isCompleted || session.answeredCurrent) {
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
    session.answeredCurrent = false;
    session.showAnswer = false;
    session.lastIsCorrect = false;
    session.lastTimeSeconds = 0;
    session.startedAtCurrent = DateTime.now();
    notifyListeners();
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
    switch (aiProvider) {
      case AiProvider.openrouter:
        explanation = await openRouterService.generateExplanation(
          questionId: question.id!,
          question: question.questionText,
          correctAnswer: question.correctAnswer,
        );
        break;
      case AiProvider.local:
        explanation = await localOnlyService.generateExplanation(
          questionId: question.id!,
          question: question.questionText,
          correctAnswer: question.correctAnswer,
        );
        break;
    }
    session.explanations[question.id!] = explanation;
    notifyListeners();
    return explanation;
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
  }) {
    return databaseService.getQuestions(
      category: category,
      difficulty: difficulty,
      searchQuery: searchQuery,
      limit: 5000,
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
