import 'dart:typed_data';

import 'package:excel/excel.dart';

import '../models/question.dart';

class ExcelParseResult {
  const ExcelParseResult({
    required this.questions,
    required this.skippedRows,
    required this.warnings,
  });

  final List<Question> questions;
  final int skippedRows;
  final List<String> warnings;
}

class ExcelParserService {
  static const Map<String, List<String>> _aliases = <String, List<String>>{
    'question': <String>[
      'вопрос',
      'question',
      'question text',
      'текст вопроса',
    ],
    'correct': <String>[
      'правильный ответ',
      'верный ответ',
      'correct answer',
      'answer',
      'ответ',
    ],
    'correct_count': <String>[
      'кол во правильных',
      'количество правильных',
      'кол во верных',
      'количество верных',
      'correct count',
      'number of correct answers',
    ],
    'wrong1': <String>[
      'неправильный ответ 1',
      'wrong answer 1',
      'incorrect answer 1',
      'вариант 1',
    ],
    'wrong2': <String>[
      'неправильный ответ 2',
      'wrong answer 2',
      'incorrect answer 2',
      'вариант 2',
    ],
    'wrong3': <String>[
      'неправильный ответ 3',
      'wrong answer 3',
      'incorrect answer 3',
      'вариант 3',
    ],
    'competency': <String>[
      'компетенция',
      'компетенции',
      'competency',
      'компетенция из мк',
      'компетенция мк',
    ],
  };

  Future<ExcelParseResult> parse({
    required Uint8List bytes,
    required String sourceFile,
  }) async {
    final excel = Excel.decodeBytes(bytes);
    final parsed = <Question>[];
    final warnings = <String>[];
    var skippedRows = 0;

    for (final entry in excel.tables.entries) {
      final sheetName = entry.key;
      final table = entry.value;
      if (table.rows.isEmpty) {
        continue;
      }

      final headers = table.rows.first
          .map((cell) => _normalize(_cellToString(cell)))
          .toList(growable: false);
      final mapped = _matchColumns(headers);
      final explicitCorrectIndexes = _matchIndexedColumns(
        headers,
        RegExp(r'^правильный( ответ)? \d+$'),
      );
      final explicitWrongIndexes = _matchIndexedColumns(
        headers,
        RegExp(r'^(неправильный ответ|неправильный|wrong answer|incorrect answer|вариант) \d+$'),
      );
      final hasLegacyCorrectColumn = mapped.containsKey('correct');
      final hasExplicitCorrectColumns = explicitCorrectIndexes.isNotEmpty;
      if (!mapped.containsKey('question') ||
          (!hasLegacyCorrectColumn && !hasExplicitCorrectColumns)) {
        warnings.add(
          "Лист '$sheetName' пропущен: не найдены колонки вопроса/правильного ответа",
        );
        continue;
      }

      for (var rowIndex = 1; rowIndex < table.rows.length; rowIndex++) {
        final row = table.rows[rowIndex];
        String readAt(int? index) {
          if (index == null || index < 0 || index >= row.length) {
            return '';
          }
          return _cellToString(row[index]).trim();
        }

        final questionText = readAt(mapped['question']);
        final correctAnswer = readAt(mapped['correct']);
        final explicitCorrectAnswers = explicitCorrectIndexes
            .map(readAt)
            .where((item) => item.isNotEmpty)
            .toList(growable: false);
        final explicitWrongAnswers = explicitWrongIndexes
            .map(readAt)
            .where((item) => item.isNotEmpty)
            .toList(growable: false);
        final inferredCorrectCount = _inferCorrectAnswerCount(
          questionText: questionText,
          explicitCountValue: readAt(mapped['correct_count']),
        );

        if (questionText.isEmpty &&
            correctAnswer.isEmpty &&
            explicitCorrectAnswers.isEmpty) {
          skippedRows += 1;
          continue;
        }
        if (questionText.isEmpty ||
            (correctAnswer.isEmpty && explicitCorrectAnswers.isEmpty)) {
          skippedRows += 1;
          warnings.add(
            "Пропуск строки ${rowIndex + 1} на листе '$sheetName' из-за пустого вопроса/ответа",
          );
          continue;
        }

        final multiCorrectAnswers = explicitCorrectAnswers.isNotEmpty
            ? explicitCorrectAnswers
            : _splitLongCorrectAnswer(
                correctAnswer,
                expectedCount: inferredCorrectCount,
              );
        final normalizedCorrectAnswers = multiCorrectAnswers
            .map((item) => item.trim())
            .where((item) => item.isNotEmpty)
            .toList(growable: false);
        final displayCorrectAnswer = normalizedCorrectAnswers.isEmpty
            ? correctAnswer
            : normalizedCorrectAnswers.length > 1
            ? normalizedCorrectAnswers.join('\n')
            : normalizedCorrectAnswers.first;
        final fallbackWrongAnswers = <String>[
          readAt(mapped['wrong1']),
          readAt(mapped['wrong2']),
          readAt(mapped['wrong3']),
        ].where((item) => item.isNotEmpty).toList(growable: false);
        final wrongAnswers = explicitWrongAnswers.isNotEmpty
            ? explicitWrongAnswers
            : fallbackWrongAnswers;

        parsed.add(
          Question(
            questionText: questionText,
            correctAnswer: displayCorrectAnswer.trim(),
            correctAnswers: normalizedCorrectAnswers,
            wrongAnswers: wrongAnswers,
            competency: readAt(mapped['competency']),
            sourceFile: sourceFile,
          ),
        );
      }
    }

    return ExcelParseResult(
      questions: parsed,
      skippedRows: skippedRows,
      warnings: warnings,
    );
  }

  Map<String, int> _matchColumns(List<String> headers) {
    final mapped = <String, int>{};
    final usedIndexes = <int>{};

    for (final target in _aliases.keys) {
      final aliases = _aliases[target]!
          .map(_normalize)
          .where((value) => value.isNotEmpty)
          .toList(growable: false);

      final exactMatch = _findHeaderMatch(
        headers: headers,
        aliases: aliases,
        usedIndexes: usedIndexes,
        matcher: (header, alias) => header == alias,
      );
      if (exactMatch != null) {
        mapped[target] = exactMatch;
        usedIndexes.add(exactMatch);
        continue;
      }

      final containsMatch = _findHeaderMatch(
        headers: headers,
        aliases: aliases,
        usedIndexes: usedIndexes,
        matcher: (header, alias) => header.contains(alias),
      );
      if (containsMatch != null) {
        mapped[target] = containsMatch;
        usedIndexes.add(containsMatch);
        continue;
      }

      // 3) Fuzzy fallback by token overlap.
      var bestScore = 0.0;
      int? bestIndex;
      for (var i = 0; i < headers.length; i++) {
        if (usedIndexes.contains(i)) {
          continue;
        }
        final header = headers[i];
        for (final alias in aliases) {
          if (_hasConflictingNumbers(header, alias)) {
            continue;
          }
          final score = _tokenScore(header, alias);
          if (score > bestScore) {
            bestScore = score;
            bestIndex = i;
          }
        }
      }
      if (bestIndex != null && bestScore >= 0.55) {
        mapped[target] = bestIndex;
        usedIndexes.add(bestIndex);
      }
    }

    return mapped;
  }

  List<int> _matchIndexedColumns(List<String> headers, RegExp pattern) {
    final matches = <MapEntry<int, int>>[];
    for (var i = 0; i < headers.length; i++) {
      final header = headers[i];
      final match = pattern.firstMatch(header);
      if (match == null) {
        continue;
      }
      final rawIndex = RegExp(r'(\d+)$').firstMatch(header)?.group(1);
      final numericIndex = int.tryParse(rawIndex ?? '') ?? (matches.length + 1);
      matches.add(MapEntry<int, int>(numericIndex, i));
    }
    matches.sort((a, b) => a.key.compareTo(b.key));
    return matches.map((entry) => entry.value).toList(growable: false);
  }

  int? _findHeaderMatch({
    required List<String> headers,
    required List<String> aliases,
    required Set<int> usedIndexes,
    required bool Function(String header, String alias) matcher,
  }) {
    for (var i = 0; i < headers.length; i++) {
      if (usedIndexes.contains(i)) {
        continue;
      }
      final header = headers[i];
      if (header.isEmpty) {
        continue;
      }
      for (final alias in aliases) {
        if (_hasConflictingNumbers(header, alias)) {
          continue;
        }
        if (matcher(header, alias)) {
          return i;
        }
      }
    }
    return null;
  }

  bool _hasConflictingNumbers(String header, String alias) {
    final headerNumbers = RegExp(
      r'\d+',
    ).allMatches(header).map((match) => match.group(0)!).toSet();
    final aliasNumbers = RegExp(
      r'\d+',
    ).allMatches(alias).map((match) => match.group(0)!).toSet();
    if (headerNumbers.isEmpty || aliasNumbers.isEmpty) {
      return false;
    }
    return headerNumbers.intersection(aliasNumbers).isEmpty;
  }

  double _tokenScore(String a, String b) {
    if (a.isEmpty || b.isEmpty) {
      return 0.0;
    }
    final aTokens = a.split(' ').where((t) => t.isNotEmpty).toSet();
    final bTokens = b.split(' ').where((t) => t.isNotEmpty).toSet();
    if (aTokens.isEmpty || bTokens.isEmpty) {
      return 0.0;
    }
    final intersection = aTokens.intersection(bTokens).length.toDouble();
    final union = aTokens.union(bTokens).length.toDouble();
    return union == 0.0 ? 0.0 : intersection / union;
  }

  String _normalize(String raw) {
    final lowered = raw.toLowerCase().trim();
    final onlyWords = lowered.replaceAll(
      RegExp(r'[^a-zа-я0-9 ]', unicode: true),
      ' ',
    );
    return onlyWords.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  String _cellToString(Data? cell) {
    if (cell == null || cell.value == null) {
      return '';
    }
    final value = cell.value;
    return value.toString();
  }

  int? _inferCorrectAnswerCount({
    required String questionText,
    required String explicitCountValue,
  }) {
    final explicit = int.tryParse(explicitCountValue.trim());
    if (explicit != null && explicit > 1) {
      return explicit;
    }
    final match = RegExp(
      r'(\d+)\s+правильн\w*\s+ответ',
      caseSensitive: false,
      unicode: true,
    ).firstMatch(questionText);
    final inferred = int.tryParse(match?.group(1) ?? '');
    if (inferred != null && inferred > 1) {
      return inferred;
    }
    return null;
  }

  List<String> _splitLongCorrectAnswer(
    String rawAnswer, {
    required int? expectedCount,
  }) {
    final trimmed = rawAnswer.trim();
    if (trimmed.isEmpty || expectedCount == null || expectedCount <= 1) {
      return trimmed.isEmpty ? const <String>[] : <String>[trimmed];
    }

    final candidates = <List<String>>[
      _splitAnswerParts(trimmed, RegExp(r'[\r\n]+')),
      _splitAnswerParts(trimmed, RegExp(r'\s*;\s*')),
      _splitAnswerParts(trimmed, RegExp(r'\s*\u2022\s*')),
      _splitAnswerParts(trimmed, RegExp(r'\s+(?=\d+[).]\s*)')),
      _splitAnswerParts(
        trimmed,
        RegExp(r'(?<=[.!?])\s+(?=[A-ZА-ЯЁ0-9])', unicode: true),
      ),
    ];

    for (final candidate in candidates) {
      if (candidate.length == expectedCount) {
        return candidate;
      }
    }
    for (final candidate in candidates) {
      if (candidate.length > 1 && candidate.length >= expectedCount - 1) {
        return candidate;
      }
    }
    return <String>[trimmed];
  }

  List<String> _splitAnswerParts(String rawAnswer, Pattern separator) {
    final parts = rawAnswer
        .split(separator)
        .map(
          (item) => item
              .replaceFirst(
                RegExp(r'^\s*(\d+|[a-zа-я])[\).:-]\s*', unicode: true),
                '',
              )
              .trim(),
        )
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
    return parts.toSet().toList(growable: false);
  }
}
