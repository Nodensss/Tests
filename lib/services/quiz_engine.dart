import 'dart:math';

import '../models/question.dart';
import 'database_service.dart';

enum StudyMode {
  quiz,
  flashcards,
  review,
  categoryDrill,
  weakSpots,
  hardQuestions,
}

class QuizEngine {
  QuizEngine({
    required this.databaseService,
    this.initialEaseFactor = 2.5,
    this.minEaseFactor = 1.3,
  });

  final DatabaseService databaseService;
  final double initialEaseFactor;
  final double minEaseFactor;

  List<String> buildOptions(
    Question question, {
    Iterable<Question> fallbackPool = const <Question>[],
    int targetCount = 4,
  }) {
    final options = <String>{};
    void addOption(String value) {
      final trimmed = value.trim();
      if (trimmed.isEmpty) {
        return;
      }
      options.add(trimmed);
    }

    addOption(question.correctAnswer);
    for (final wrong in question.wrongAnswers) {
      addOption(wrong);
    }

    if (options.length < targetCount) {
      final questionTextKey = question.questionText.trim().toLowerCase();
      final questionId = question.id;
      final correctLower = question.correctAnswer.trim().toLowerCase();

      final fallbackCandidates = <String>[];
      for (final candidate in fallbackPool) {
        final sameById =
            questionId != null &&
            candidate.id != null &&
            questionId == candidate.id;
        final sameByText =
            candidate.questionText.trim().toLowerCase() == questionTextKey;
        if (sameById || sameByText) {
          continue;
        }
        fallbackCandidates.add(candidate.correctAnswer);
        fallbackCandidates.addAll(candidate.wrongAnswers);
      }

      fallbackCandidates.shuffle(Random());
      for (final value in fallbackCandidates) {
        final trimmed = value.trim();
        if (trimmed.isEmpty) {
          continue;
        }
        if (trimmed.toLowerCase() == correctLower) {
          continue;
        }
        options.add(trimmed);
        if (options.length >= targetCount) {
          break;
        }
      }
    }

    final shuffled = options.toList(growable: false);
    shuffled.shuffle(Random());
    return shuffled;
  }

  Future<List<Question>> loadQuestionsForMode({
    required StudyMode mode,
    required int limit,
    String? category,
    int? difficulty,
  }) async {
    switch (mode) {
      case StudyMode.review:
        final rows = await databaseService.questionsForReview(limit: limit);
        return rows.map(Question.fromMap).toList(growable: false);
      case StudyMode.weakSpots:
        final weak = await databaseService.weakestCategories(limit: 3);
        if (weak.isEmpty) {
          return databaseService.getRandomQuestions(
            limit: limit,
            category: category,
            difficulty: difficulty,
          );
        }
        final pool = <Question>[];
        final chunk = max(1, (limit / weak.length).ceil());
        for (final item in weak) {
          pool.addAll(
            await databaseService.getRandomQuestions(
              limit: chunk,
              category: item['category']?.toString(),
              difficulty: difficulty,
            ),
          );
        }
        pool.shuffle(Random());
        return pool.take(limit).toList(growable: false);
      case StudyMode.categoryDrill:
        final byCategory = await databaseService.getQuestions(
          category: category,
          difficulty: difficulty,
          limit: 5000,
        );
        final sorted = List<Question>.from(byCategory)
          ..sort((a, b) => a.difficulty.compareTo(b.difficulty));
        return sorted.take(limit).toList(growable: false);
      case StudyMode.hardQuestions:
        return databaseService.getRandomQuestions(
          limit: limit,
          category: category,
          difficulty: difficulty,
          onlyHard: true,
        );
      case StudyMode.flashcards:
      case StudyMode.quiz:
        return databaseService.getRandomQuestions(
          limit: limit,
          category: category,
          difficulty: difficulty,
        );
    }
  }

  Future<String> startSession({
    required StudyMode mode,
    required int totalQuestions,
    String? categoryFilter,
  }) async {
    final modeName = switch (mode) {
      StudyMode.quiz => 'quiz',
      StudyMode.flashcards => 'flashcard',
      StudyMode.review => 'review',
      StudyMode.categoryDrill => 'category_drill',
      StudyMode.weakSpots => 'weak_spots',
      StudyMode.hardQuestions => 'hard_questions',
    };
    return databaseService.startSession(
      sessionType: modeName,
      categoryFilter: categoryFilter,
      totalQuestions: totalQuestions,
    );
  }

  Future<void> finishSession({
    required String sessionId,
    required int totalQuestions,
    required int correctAnswers,
  }) {
    return databaseService.finishSession(
      sessionId: sessionId,
      totalQuestions: totalQuestions,
      correctAnswers: correctAnswers,
    );
  }

  Future<void> recordAnswer({
    required Question question,
    required String userAnswer,
    required bool isCorrect,
    required double timeSpentSeconds,
    required String sessionId,
    required int quality,
  }) async {
    final questionId = question.id;
    if (questionId == null) {
      return;
    }
    await databaseService.recordAnswer(
      questionId: questionId,
      userAnswer: userAnswer,
      isCorrect: isCorrect,
      timeSpentSeconds: timeSpentSeconds,
      sessionId: sessionId,
    );
    await _updateSpacedRepetition(questionId: questionId, quality: quality);
  }

  Future<void> _updateSpacedRepetition({
    required int questionId,
    required int quality,
  }) async {
    final q = quality.clamp(0, 5);
    final spaced = await databaseService.getSpacedData(questionId);
    final currentEase =
        (spaced['ease_factor'] as num?)?.toDouble() ?? initialEaseFactor;
    final currentInterval = (spaced['interval_days'] as int?) ?? 1;
    final currentRepetitions = (spaced['repetitions'] as int?) ?? 0;

    final (newEase, newInterval, newRepetitions) = calculateSm2(
      easeFactor: currentEase,
      intervalDays: currentInterval,
      repetitions: currentRepetitions,
      quality: q,
    );

    await databaseService.updateSpacedData(
      questionId: questionId,
      easeFactor: newEase,
      intervalDays: newInterval,
      repetitions: newRepetitions,
      nextReviewDate: DateTime.now().add(Duration(days: newInterval)),
    );
  }

  (double easeFactor, int intervalDays, int repetitions) calculateSm2({
    required double easeFactor,
    required int intervalDays,
    required int repetitions,
    required int quality,
  }) {
    var ef = easeFactor;
    var interval = intervalDays;
    var reps = repetitions;

    if (quality >= 3) {
      if (reps == 0) {
        interval = 1;
      } else if (reps == 1) {
        interval = 6;
      } else {
        interval = max(1, (interval * ef).round());
      }
      reps += 1;
    } else {
      reps = 0;
      interval = 1;
    }

    ef = max(
      minEaseFactor,
      ef + (0.1 - (5 - quality) * (0.08 + (5 - quality) * 0.02)),
    );

    return (ef, interval, reps);
  }

  int qualityFromQuiz({
    required bool isCorrect,
    required double timeSpentSeconds,
  }) {
    if (!isCorrect) {
      return 2;
    }
    if (timeSpentSeconds <= 5) {
      return 5;
    }
    if (timeSpentSeconds <= 12) {
      return 4;
    }
    return 3;
  }

  int qualityFromFlashcardLabel(String label) {
    switch (label) {
      case 'Знал':
        return 5;
      case 'Частично':
        return 3;
      case 'Не знал':
        return 1;
      default:
        return 3;
    }
  }
}
