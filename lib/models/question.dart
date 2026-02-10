import 'dart:convert';

class Question {
  const Question({
    this.id,
    required this.questionText,
    required this.correctAnswer,
    required this.wrongAnswers,
    this.competency,
    this.category,
    this.subcategory,
    this.difficulty = 3,
    this.keywords = const <String>[],
    this.explanation,
    this.sourceFile,
    this.createdAt,
  });

  final int? id;
  final String questionText;
  final String correctAnswer;
  final List<String> wrongAnswers;
  final String? competency;
  final String? category;
  final String? subcategory;
  final int difficulty;
  final List<String> keywords;
  final String? explanation;
  final String? sourceFile;
  final DateTime? createdAt;

  Question copyWith({
    int? id,
    String? questionText,
    String? correctAnswer,
    List<String>? wrongAnswers,
    String? competency,
    String? category,
    String? subcategory,
    int? difficulty,
    List<String>? keywords,
    String? explanation,
    String? sourceFile,
    DateTime? createdAt,
  }) {
    return Question(
      id: id ?? this.id,
      questionText: questionText ?? this.questionText,
      correctAnswer: correctAnswer ?? this.correctAnswer,
      wrongAnswers: wrongAnswers ?? this.wrongAnswers,
      competency: competency ?? this.competency,
      category: category ?? this.category,
      subcategory: subcategory ?? this.subcategory,
      difficulty: difficulty ?? this.difficulty,
      keywords: keywords ?? this.keywords,
      explanation: explanation ?? this.explanation,
      sourceFile: sourceFile ?? this.sourceFile,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, Object?> toMap() {
    final normalizedWrongAnswers = List<String>.from(wrongAnswers);
    while (normalizedWrongAnswers.length < 3) {
      normalizedWrongAnswers.add('');
    }
    return <String, Object?>{
      'id': id,
      'question_text': questionText,
      'correct_answer': correctAnswer,
      'wrong_answer_1': normalizedWrongAnswers[0],
      'wrong_answer_2': normalizedWrongAnswers[1],
      'wrong_answer_3': normalizedWrongAnswers[2],
      'competency': competency,
      'category': category,
      'subcategory': subcategory,
      'difficulty': difficulty,
      'keywords': jsonEncode(keywords),
      'explanation': explanation,
      'source_file': sourceFile,
      'created_at': createdAt?.toIso8601String(),
    };
  }

  factory Question.fromMap(Map<String, Object?> map) {
    final rawKeywords = map['keywords'];
    List<String> parsedKeywords;
    if (rawKeywords is String && rawKeywords.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(rawKeywords);
        if (decoded is List) {
          parsedKeywords =
              decoded.map((item) => item.toString()).toList(growable: false);
        } else {
          parsedKeywords = const <String>[];
        }
      } catch (_) {
        parsedKeywords = const <String>[];
      }
    } else {
      parsedKeywords = const <String>[];
    }

    return Question(
      id: map['id'] as int?,
      questionText: (map['question_text'] ?? '').toString(),
      correctAnswer: (map['correct_answer'] ?? '').toString(),
      wrongAnswers: <String>[
        (map['wrong_answer_1'] ?? '').toString(),
        (map['wrong_answer_2'] ?? '').toString(),
        (map['wrong_answer_3'] ?? '').toString(),
      ],
      competency: map['competency']?.toString(),
      category: map['category']?.toString(),
      subcategory: map['subcategory']?.toString(),
      difficulty: map['difficulty'] is int
          ? map['difficulty'] as int
          : int.tryParse((map['difficulty'] ?? 3).toString()) ?? 3,
      keywords: parsedKeywords,
      explanation: map['explanation']?.toString(),
      sourceFile: map['source_file']?.toString(),
      createdAt: map['created_at'] == null
          ? null
          : DateTime.tryParse(map['created_at'].toString()),
    );
  }
}
