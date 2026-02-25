import 'dart:math';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../models/question.dart';

class AddQuestionsProgress {
  const AddQuestionsProgress({
    required this.processed,
    required this.total,
    required this.changed,
  });

  final int processed;
  final int total;
  final int changed;
}

typedef AddQuestionsProgressCallback =
    void Function(AddQuestionsProgress progress);
typedef QuestionKeyProgressCallback = void Function(int processed, int total);

class DatabaseService {
  DatabaseService._();

  static final DatabaseService instance = DatabaseService._();
  static const _uuid = Uuid();

  Database? _db;

  Future<Database> get database async {
    if (_db != null) {
      return _db!;
    }
    _db = await _open();
    return _db!;
  }

  Future<Database> _open() async {
    final basePath = await getDatabasesPath();
    final dbPath = p.join(basePath, 'quiz_trainer_flutter.db');
    return openDatabase(
      dbPath,
      version: 3,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE questions (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            question_text TEXT NOT NULL,
            correct_answer TEXT NOT NULL,
            wrong_answer_1 TEXT,
            wrong_answer_2 TEXT,
            wrong_answer_3 TEXT,
            is_hard INTEGER DEFAULT 0,
            competency TEXT,
            category TEXT,
            subcategory TEXT,
            difficulty INTEGER DEFAULT 3,
            keywords TEXT,
            explanation TEXT,
            source_file TEXT,
            created_at TEXT DEFAULT CURRENT_TIMESTAMP
          );
        ''');

        await db.execute('''
          CREATE UNIQUE INDEX idx_questions_unique
          ON questions (
            question_text,
            correct_answer,
            COALESCE(wrong_answer_1, ''),
            COALESCE(wrong_answer_2, ''),
            COALESCE(wrong_answer_3, '')
          );
        ''');

        await db.execute('''
          CREATE TABLE user_answers (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            question_id INTEGER NOT NULL,
            user_answer TEXT,
            is_correct INTEGER NOT NULL,
            time_spent_seconds REAL,
            session_id TEXT,
            answered_at TEXT DEFAULT CURRENT_TIMESTAMP,
            FOREIGN KEY (question_id) REFERENCES questions(id) ON DELETE CASCADE
          );
        ''');

        await db.execute('''
          CREATE TABLE study_sessions (
            id TEXT PRIMARY KEY,
            session_type TEXT NOT NULL,
            category_filter TEXT,
            total_questions INTEGER,
            correct_answers INTEGER,
            started_at TEXT,
            finished_at TEXT
          );
        ''');

        await db.execute('''
          CREATE TABLE spaced_repetition (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            question_id INTEGER UNIQUE NOT NULL,
            ease_factor REAL DEFAULT 2.5,
            interval_days INTEGER DEFAULT 1,
            repetitions INTEGER DEFAULT 0,
            next_review_date TEXT,
            FOREIGN KEY (question_id) REFERENCES questions(id) ON DELETE CASCADE
          );
        ''');

        await db.execute('''
          CREATE TABLE ai_cache (
            cache_key TEXT PRIMARY KEY,
            cache_type TEXT NOT NULL,
            payload TEXT NOT NULL,
            created_at TEXT DEFAULT CURRENT_TIMESTAMP
          );
        ''');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute('ALTER TABLE questions ADD COLUMN competency TEXT;');
        }
        if (oldVersion < 3) {
          await db.execute(
            'ALTER TABLE questions ADD COLUMN is_hard INTEGER DEFAULT 0;',
          );
        }
      },
    );
  }

  Future<int> addQuestions(
    List<Question> questions, {
    AddQuestionsProgressCallback? onProgress,
  }) async {
    if (questions.isEmpty) {
      return 0;
    }
    final db = await database;
    var changed = 0;
    var processed = 0;
    final total = questions.length;
    const chunkSize = 200;

    onProgress?.call(
      AddQuestionsProgress(processed: 0, total: total, changed: 0),
    );

    for (var offset = 0; offset < total; offset += chunkSize) {
      final end = min(offset + chunkSize, total);
      final chunk = questions.sublist(offset, end);

      await db.transaction((txn) async {
        for (final question in chunk) {
          if (question.questionText.trim().isEmpty ||
              question.correctAnswer.trim().isEmpty) {
            processed += 1;
            if (processed % 20 == 0 || processed == total) {
              onProgress?.call(
                AddQuestionsProgress(
                  processed: processed,
                  total: total,
                  changed: changed,
                ),
              );
            }
            continue;
          }
          final normalizedQuestionText = question.questionText.trim();
          final normalizedCorrectAnswer = question.correctAnswer.trim();
          final wrong1 = question.wrongAnswers.isNotEmpty
              ? question.wrongAnswers[0]
              : '';
          final wrong2 = question.wrongAnswers.length > 1
              ? question.wrongAnswers[1]
              : '';
          final wrong3 = question.wrongAnswers.length > 2
              ? question.wrongAnswers[2]
              : '';
          final competency = question.competency?.trim() ?? '';

          final brokenRows = await txn.rawQuery(
            '''
            SELECT id
            FROM questions
            WHERE question_text = ?
              AND correct_answer = ?
              AND (
                (
                  TRIM(COALESCE(wrong_answer_1, '')) = ''
                  AND TRIM(COALESCE(wrong_answer_2, '')) = ''
                  AND TRIM(COALESCE(wrong_answer_3, '')) = ''
                )
                OR (
                  LOWER(TRIM(COALESCE(wrong_answer_1, ''))) = LOWER(TRIM(?))
                  AND LOWER(TRIM(COALESCE(wrong_answer_2, ''))) = LOWER(TRIM(?))
                  AND LOWER(TRIM(COALESCE(wrong_answer_3, ''))) = LOWER(TRIM(?))
                )
              )
            ORDER BY id DESC
            LIMIT 1
            ''',
            <Object?>[
              normalizedQuestionText,
              normalizedCorrectAnswer,
              normalizedCorrectAnswer,
              normalizedCorrectAnswer,
              normalizedCorrectAnswer,
            ],
          );
          if (brokenRows.isNotEmpty) {
            final brokenId = brokenRows.first['id'] as int?;
            if (brokenId != null) {
              final repaired = await txn.update(
                'questions',
                <String, Object?>{
                  'wrong_answer_1': wrong1,
                  'wrong_answer_2': wrong2,
                  'wrong_answer_3': wrong3,
                  'competency': competency.isEmpty ? null : competency,
                  'category': question.category,
                  'subcategory': question.subcategory,
                  'difficulty': question.difficulty,
                  'keywords': question.toMap()['keywords'],
                  'source_file': question.sourceFile,
                  if (question.explanation != null)
                    'explanation': question.explanation,
                },
                where: 'id = ?',
                whereArgs: <Object?>[brokenId],
              );
              if (repaired > 0) {
                changed += repaired;
                processed += 1;
                if (processed % 20 == 0 || processed == total) {
                  onProgress?.call(
                    AddQuestionsProgress(
                      processed: processed,
                      total: total,
                      changed: changed,
                    ),
                  );
                }
                continue;
              }
            }
          }

          final insertedId = await txn.rawInsert(
            '''
            INSERT OR IGNORE INTO questions (
              question_text, correct_answer, wrong_answer_1, wrong_answer_2, wrong_answer_3,
              is_hard, competency, category, subcategory, difficulty, keywords, explanation, source_file, created_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ''',
            <Object?>[
              normalizedQuestionText,
              normalizedCorrectAnswer,
              wrong1,
              wrong2,
              wrong3,
              question.isHard ? 1 : 0,
              competency.isEmpty ? null : competency,
              question.category,
              question.subcategory,
              question.difficulty,
              question.toMap()['keywords'],
              question.explanation,
              question.sourceFile,
              question.createdAt?.toIso8601String() ??
                  DateTime.now().toIso8601String(),
            ],
          );
          if (insertedId > 0) {
            changed += 1;
            processed += 1;
            if (processed % 20 == 0 || processed == total) {
              onProgress?.call(
                AddQuestionsProgress(
                  processed: processed,
                  total: total,
                  changed: changed,
                ),
              );
            }
            continue;
          }

          // If question already exists, refresh category/metadata from new import.
          final updated = await txn.rawUpdate(
            '''
            UPDATE questions
            SET
              is_hard = CASE WHEN ? = 1 THEN 1 ELSE is_hard END,
              competency = CASE WHEN ? = '' THEN competency ELSE ? END,
              category = ?,
              subcategory = ?,
              difficulty = ?,
              keywords = ?,
              source_file = COALESCE(?, source_file),
              explanation = COALESCE(?, explanation)
            WHERE question_text = ?
              AND correct_answer = ?
              AND COALESCE(wrong_answer_1, '') = ?
              AND COALESCE(wrong_answer_2, '') = ?
              AND COALESCE(wrong_answer_3, '') = ?
            ''',
            <Object?>[
              question.isHard ? 1 : 0,
              competency,
              competency,
              question.category,
              question.subcategory,
              question.difficulty,
              question.toMap()['keywords'],
              question.sourceFile,
              question.explanation,
              normalizedQuestionText,
              normalizedCorrectAnswer,
              wrong1,
              wrong2,
              wrong3,
            ],
          );
          if (updated > 0) {
            changed += updated;
          }
          processed += 1;
          if (processed % 20 == 0 || processed == total) {
            onProgress?.call(
              AddQuestionsProgress(
                processed: processed,
                total: total,
                changed: changed,
              ),
            );
          }
        }
      });
    }

    await db.execute('''
      INSERT OR IGNORE INTO spaced_repetition (question_id, next_review_date)
      SELECT q.id, DATE('now')
      FROM questions q
      LEFT JOIN spaced_repetition sr ON sr.question_id = q.id
      WHERE sr.question_id IS NULL;
    ''');

    onProgress?.call(
      AddQuestionsProgress(processed: total, total: total, changed: changed),
    );

    return changed;
  }

  Future<int> questionsCount() async {
    final db = await database;
    final row = await db.rawQuery('SELECT COUNT(*) AS cnt FROM questions');
    return (row.first['cnt'] as int?) ?? 0;
  }

  String _normalizeQuestionKeyPart(String value) {
    return value.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  String _buildNormalizedQuestionKey({
    required String questionText,
    required String correctAnswer,
    required String wrong1,
    required String wrong2,
    required String wrong3,
  }) {
    return <String>[
      _normalizeQuestionKeyPart(questionText),
      _normalizeQuestionKeyPart(correctAnswer),
      _normalizeQuestionKeyPart(wrong1),
      _normalizeQuestionKeyPart(wrong2),
      _normalizeQuestionKeyPart(wrong3),
    ].join('||');
  }

  Future<Set<String>> getNormalizedQuestionKeys({
    QuestionKeyProgressCallback? onProgress,
  }) async {
    final db = await database;
    final total = await questionsCount();
    if (total <= 0) {
      onProgress?.call(0, 0);
      return <String>{};
    }

    final rows = await db.rawQuery('''
      SELECT
        question_text,
        correct_answer,
        COALESCE(wrong_answer_1, '') AS wrong_answer_1,
        COALESCE(wrong_answer_2, '') AS wrong_answer_2,
        COALESCE(wrong_answer_3, '') AS wrong_answer_3
      FROM questions
    ''');

    final keys = <String>{};
    for (var i = 0; i < rows.length; i++) {
      final row = rows[i];
      keys.add(
        _buildNormalizedQuestionKey(
          questionText: (row['question_text'] ?? '').toString(),
          correctAnswer: (row['correct_answer'] ?? '').toString(),
          wrong1: (row['wrong_answer_1'] ?? '').toString(),
          wrong2: (row['wrong_answer_2'] ?? '').toString(),
          wrong3: (row['wrong_answer_3'] ?? '').toString(),
        ),
      );
      if ((i + 1) % 200 == 0 || i + 1 == rows.length) {
        onProgress?.call(i + 1, total);
      }
    }
    return keys;
  }

  Future<int> countQuestions({
    String? category,
    List<String>? categories,
    int? difficulty,
    String? searchQuery,
    bool onlyHard = false,
  }) async {
    final db = await database;
    final where = <String>['1 = 1'];
    final args = <Object?>[];

    if (onlyHard) {
      where.add('COALESCE(is_hard, 0) = 1');
    }
    _addCategoryFilter(
      where: where,
      args: args,
      category: category,
      categories: categories,
    );
    if (difficulty != null) {
      where.add('difficulty = ?');
      args.add(difficulty);
    }
    if (searchQuery != null && searchQuery.trim().isNotEmpty) {
      final like = '%${searchQuery.trim()}%';
      where.add('''
        (
          question_text LIKE ? OR
          correct_answer LIKE ? OR
          COALESCE(wrong_answer_1, '') LIKE ? OR
          COALESCE(wrong_answer_2, '') LIKE ? OR
          COALESCE(wrong_answer_3, '') LIKE ? OR
          COALESCE(category, '') LIKE ? OR
          COALESCE(competency, '') LIKE ?
        )
      ''');
      args.addAll(List<Object?>.filled(7, like));
    }

    final rows = await db.rawQuery('''
      SELECT COUNT(*) AS cnt
      FROM questions
      WHERE ${where.join(' AND ')}
      ''', args);
    return (rows.first['cnt'] as int?) ?? 0;
  }

  Future<List<Question>> getQuestions({
    String? category,
    List<String>? categories,
    int? difficulty,
    String? searchQuery,
    bool onlyHard = false,
    int limit = 1000,
  }) async {
    final db = await database;
    final where = <String>['1 = 1'];
    final args = <Object?>[];

    if (onlyHard) {
      where.add('COALESCE(is_hard, 0) = 1');
    }
    _addCategoryFilter(
      where: where,
      args: args,
      category: category,
      categories: categories,
    );
    if (difficulty != null) {
      where.add('difficulty = ?');
      args.add(difficulty);
    }
    if (searchQuery != null && searchQuery.trim().isNotEmpty) {
      final like = '%${searchQuery.trim()}%';
      where.add('''
        (
          question_text LIKE ? OR
          correct_answer LIKE ? OR
          COALESCE(wrong_answer_1, '') LIKE ? OR
          COALESCE(wrong_answer_2, '') LIKE ? OR
          COALESCE(wrong_answer_3, '') LIKE ? OR
          COALESCE(category, '') LIKE ? OR
          COALESCE(competency, '') LIKE ?
        )
      ''');
      args.addAll(List<Object?>.filled(7, like));
    }

    final rows = await db.rawQuery(
      '''
      SELECT *
      FROM questions
      WHERE ${where.join(' AND ')}
      ORDER BY id DESC
      LIMIT ?
      ''',
      <Object?>[...args, limit],
    );

    return rows.map(Question.fromMap).toList(growable: false);
  }

  Future<List<Question>> getRandomQuestions({
    int limit = 20,
    String? category,
    List<String>? categories,
    int? difficulty,
    bool onlyHard = false,
  }) async {
    final rows = await getQuestions(
      category: category,
      categories: categories,
      difficulty: difficulty,
      onlyHard: onlyHard,
      limit: 5000,
    );
    rows.shuffle(Random());
    if (rows.length <= limit) {
      return rows;
    }
    return rows.take(limit).toList(growable: false);
  }

  Future<List<String>> getCategories() async {
    final db = await database;
    final rows = await db.rawQuery('''
      SELECT DISTINCT
        COALESCE(NULLIF(competency, ''), COALESCE(NULLIF(category, ''), 'Без категории')) AS category
      FROM questions
      ORDER BY category
    ''');
    return rows.map((row) => row['category'].toString()).toList();
  }

  void _addCategoryFilter({
    required List<String> where,
    required List<Object?> args,
    String? category,
    List<String>? categories,
  }) {
    final normalized = <String>{
      if (category != null &&
          category.trim().isNotEmpty &&
          category.trim() != 'Все')
        category.trim(),
      ...?categories
          ?.map((item) => item.trim())
          .where((item) => item.isNotEmpty && item != 'Все'),
    }.toList(growable: false);

    if (normalized.isEmpty) {
      return;
    }

    final placeholders = List<String>.filled(normalized.length, '?').join(',');
    where.add(
      "COALESCE(NULLIF(competency, ''), COALESCE(NULLIF(category, ''), 'Без категории')) IN ($placeholders)",
    );
    args.addAll(normalized);
  }

  Future<String> startSession({
    required String sessionType,
    String? categoryFilter,
    required int totalQuestions,
  }) async {
    final db = await database;
    final id = _uuid.v4();
    await db.insert('study_sessions', <String, Object?>{
      'id': id,
      'session_type': sessionType,
      'category_filter': categoryFilter,
      'total_questions': totalQuestions,
      'correct_answers': 0,
      'started_at': DateTime.now().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    return id;
  }

  Future<void> finishSession({
    required String sessionId,
    required int totalQuestions,
    required int correctAnswers,
  }) async {
    final db = await database;
    await db.update(
      'study_sessions',
      <String, Object?>{
        'total_questions': totalQuestions,
        'correct_answers': correctAnswers,
        'finished_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: <Object?>[sessionId],
    );
  }

  Future<void> recordAnswer({
    required int questionId,
    required String userAnswer,
    required bool isCorrect,
    required double timeSpentSeconds,
    required String sessionId,
  }) async {
    final db = await database;
    await db.insert('user_answers', <String, Object?>{
      'question_id': questionId,
      'user_answer': userAnswer,
      'is_correct': isCorrect ? 1 : 0,
      'time_spent_seconds': timeSpentSeconds,
      'session_id': sessionId,
      'answered_at': DateTime.now().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.abort);
  }

  Future<Map<String, Object>> getUserStatistics() async {
    final db = await database;
    final overall = await db.rawQuery('''
      SELECT
        COUNT(*) AS total_answers,
        COALESCE(SUM(CASE WHEN is_correct = 1 THEN 1 ELSE 0 END), 0) AS correct_answers,
        COALESCE(AVG(time_spent_seconds), 0) AS avg_time,
        COALESCE(SUM(time_spent_seconds), 0) AS total_time
      FROM user_answers
    ''');
    final totalQuestions = await questionsCount();
    final sessionsRow = await db.rawQuery(
      'SELECT COUNT(*) AS cnt FROM study_sessions',
    );
    final streakRows = await db.rawQuery('''
      SELECT is_correct
      FROM user_answers
      ORDER BY answered_at DESC
      LIMIT 300
    ''');

    var streak = 0;
    for (final row in streakRows) {
      if ((row['is_correct'] as int? ?? 0) == 1) {
        streak += 1;
      } else {
        break;
      }
    }

    final totalAnswers = (overall.first['total_answers'] as int?) ?? 0;
    final correctAnswers = (overall.first['correct_answers'] as int?) ?? 0;
    final accuracy = totalAnswers == 0
        ? 0.0
        : ((correctAnswers / totalAnswers) * 100.0);

    return <String, Object>{
      'total_questions': totalQuestions,
      'total_answers': totalAnswers,
      'correct_answers': correctAnswers,
      'accuracy_pct': accuracy,
      'avg_time_seconds':
          (overall.first['avg_time'] as num?)?.toDouble() ?? 0.0,
      'total_time_seconds':
          (overall.first['total_time'] as num?)?.toDouble() ?? 0.0,
      'total_sessions': (sessionsRow.first['cnt'] as int?) ?? 0,
      'streak': streak,
    };
  }

  Future<List<Map<String, Object?>>> getCategoryStatistics() async {
    final db = await database;
    final rows = await db.rawQuery('''
      SELECT
        COALESCE(NULLIF(q.competency, ''), COALESCE(NULLIF(q.category, ''), 'Без категории')) AS category,
        COUNT(DISTINCT q.id) AS total_questions,
        COUNT(ua.id) AS total_attempts,
        COALESCE(SUM(CASE WHEN ua.is_correct = 1 THEN 1 ELSE 0 END), 0) AS correct_attempts,
        CASE
          WHEN COUNT(ua.id) = 0 THEN 0
          ELSE ROUND(
            100.0 * SUM(CASE WHEN ua.is_correct = 1 THEN 1 ELSE 0 END) / COUNT(ua.id),
            2
          )
        END AS accuracy_pct
      FROM questions q
      LEFT JOIN user_answers ua ON ua.question_id = q.id
      GROUP BY category
      ORDER BY total_questions DESC, category ASC
    ''');
    return rows;
  }

  Future<List<Map<String, Object?>>> getProgressByDay({int days = 30}) async {
    final db = await database;
    return db.rawQuery('''
      SELECT
        SUBSTR(answered_at, 1, 10) AS day,
        COUNT(*) AS total_attempts,
        SUM(CASE WHEN is_correct = 1 THEN 1 ELSE 0 END) AS correct_attempts,
        ROUND(100.0 * SUM(CASE WHEN is_correct = 1 THEN 1 ELSE 0 END) / COUNT(*), 2) AS accuracy_pct
      FROM user_answers
      WHERE DATE(answered_at) >= DATE('now', '-$days day')
      GROUP BY SUBSTR(answered_at, 1, 10)
      ORDER BY SUBSTR(answered_at, 1, 10)
    ''');
  }

  Future<List<double>> getResponseTimeDistribution() async {
    final db = await database;
    final rows = await db.rawQuery('''
      SELECT time_spent_seconds
      FROM user_answers
      WHERE time_spent_seconds IS NOT NULL
    ''');
    return rows
        .map((row) => (row['time_spent_seconds'] as num?)?.toDouble() ?? 0.0)
        .toList(growable: false);
  }

  Future<List<Map<String, Object?>>> weakestCategories({int limit = 5}) async {
    final db = await database;
    return db.rawQuery('''
      SELECT
        COALESCE(NULLIF(q.competency, ''), COALESCE(NULLIF(q.category, ''), 'Без категории')) AS category,
        COUNT(*) AS attempts,
        SUM(CASE WHEN ua.is_correct = 1 THEN 1 ELSE 0 END) AS correct_attempts,
        ROUND(100.0 * SUM(CASE WHEN ua.is_correct = 1 THEN 1 ELSE 0 END) / COUNT(*), 2) AS accuracy_pct
      FROM user_answers ua
      JOIN questions q ON q.id = ua.question_id
      GROUP BY category
      HAVING COUNT(*) > 0
      ORDER BY accuracy_pct ASC, attempts DESC
      LIMIT $limit
    ''');
  }

  Future<List<Map<String, Object?>>> questionsForReview({
    int limit = 20,
  }) async {
    final db = await database;
    final rows = await db.rawQuery('''
      SELECT
        q.*,
        sr.ease_factor,
        sr.interval_days,
        sr.repetitions,
        sr.next_review_date,
        COALESCE(ws.wrong_attempts, 0) AS wrong_attempts
      FROM spaced_repetition sr
      JOIN questions q ON q.id = sr.question_id
      LEFT JOIN (
        SELECT
          question_id,
          SUM(CASE WHEN is_correct = 0 THEN 1 ELSE 0 END) AS wrong_attempts
        FROM user_answers
        GROUP BY question_id
      ) ws ON ws.question_id = q.id
      WHERE DATE(sr.next_review_date) <= DATE('now')
      ORDER BY wrong_attempts DESC, DATE(sr.next_review_date) ASC
      LIMIT $limit
    ''');
    return rows;
  }

  Future<Map<String, Object?>> getSpacedData(int questionId) async {
    final db = await database;
    final rows = await db.query(
      'spaced_repetition',
      where: 'question_id = ?',
      whereArgs: <Object?>[questionId],
      limit: 1,
    );
    if (rows.isEmpty) {
      final defaults = <String, Object?>{
        'question_id': questionId,
        'ease_factor': 2.5,
        'interval_days': 1,
        'repetitions': 0,
        'next_review_date': DateTime.now().toIso8601String().substring(0, 10),
      };
      await db.insert(
        'spaced_repetition',
        defaults,
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
      return defaults;
    }
    return rows.first;
  }

  Future<void> updateSpacedData({
    required int questionId,
    required double easeFactor,
    required int intervalDays,
    required int repetitions,
    required DateTime nextReviewDate,
  }) async {
    final db = await database;
    await db.insert('spaced_repetition', <String, Object?>{
      'question_id': questionId,
      'ease_factor': easeFactor,
      'interval_days': intervalDays,
      'repetitions': repetitions,
      'next_review_date': nextReviewDate.toIso8601String().substring(0, 10),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<int> dueReviewCount() async {
    final db = await database;
    final row = await db.rawQuery('''
      SELECT COUNT(*) AS cnt
      FROM spaced_repetition
      WHERE DATE(next_review_date) <= DATE('now')
    ''');
    return (row.first['cnt'] as int?) ?? 0;
  }

  Future<String?> getCache(String cacheKey) async {
    final db = await database;
    final rows = await db.query(
      'ai_cache',
      columns: <String>['payload'],
      where: 'cache_key = ?',
      whereArgs: <Object?>[cacheKey],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return rows.first['payload']?.toString();
  }

  Future<void> setCache({
    required String cacheKey,
    required String cacheType,
    required String payload,
  }) async {
    final db = await database;
    await db.insert('ai_cache', <String, Object?>{
      'cache_key': cacheKey,
      'cache_type': cacheType,
      'payload': payload,
      'created_at': DateTime.now().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> clearAllData() async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.execute('DELETE FROM user_answers;');
      await txn.execute('DELETE FROM study_sessions;');
      await txn.execute('DELETE FROM spaced_repetition;');
      await txn.execute('DELETE FROM questions;');
      await txn.execute('DELETE FROM ai_cache;');
      await txn.execute(
        "DELETE FROM sqlite_sequence WHERE name IN ('questions', 'user_answers', 'spaced_repetition');",
      );
    });
  }

  Future<void> updateQuestionCategory({
    required int questionId,
    required String category,
    String? competency,
    String? subcategory,
    int? difficulty,
  }) async {
    final db = await database;
    await db.update(
      'questions',
      <String, Object?>{
        'category': category,
        if (competency != null) 'competency': competency,
        'subcategory': subcategory,
        if (difficulty != null) 'difficulty': difficulty,
      },
      where: 'id = ?',
      whereArgs: <Object?>[questionId],
    );
  }

  Future<void> updateQuestionExplanation({
    required int questionId,
    required String explanation,
  }) async {
    final db = await database;
    await db.update(
      'questions',
      <String, Object?>{'explanation': explanation},
      where: 'id = ?',
      whereArgs: <Object?>[questionId],
    );
  }

  Future<void> deleteQuestion(int questionId) async {
    final db = await database;
    await db.delete(
      'questions',
      where: 'id = ?',
      whereArgs: <Object?>[questionId],
    );
  }

  Future<void> updateQuestionCompetency({
    required int questionId,
    required String competency,
  }) async {
    final db = await database;
    await db.update(
      'questions',
      <String, Object?>{'competency': competency},
      where: 'id = ?',
      whereArgs: <Object?>[questionId],
    );
  }

  Future<void> setQuestionHardStatus({
    required int questionId,
    required bool isHard,
  }) async {
    final db = await database;
    await db.update(
      'questions',
      <String, Object?>{'is_hard': isHard ? 1 : 0},
      where: 'id = ?',
      whereArgs: <Object?>[questionId],
    );
  }

  Future<List<Question>> getQuestionsWithoutCompetency({
    int limit = 5000,
  }) async {
    final db = await database;
    final rows = await db.rawQuery(
      '''
      SELECT *
      FROM questions
      WHERE competency IS NULL OR TRIM(competency) = ''
      ORDER BY id ASC
      LIMIT ?
      ''',
      <Object?>[limit],
    );
    return rows.map(Question.fromMap).toList(growable: false);
  }
}
