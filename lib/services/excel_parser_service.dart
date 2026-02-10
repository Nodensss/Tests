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
      if (!mapped.containsKey('question') || !mapped.containsKey('correct')) {
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
        if (questionText.isEmpty && correctAnswer.isEmpty) {
          skippedRows += 1;
          continue;
        }
        if (questionText.isEmpty || correctAnswer.isEmpty) {
          skippedRows += 1;
          warnings.add(
            "Пропуск строки ${rowIndex + 1} на листе '$sheetName' из-за пустого вопроса/ответа",
          );
          continue;
        }

        parsed.add(
          Question(
            questionText: questionText,
            correctAnswer: correctAnswer,
            wrongAnswers: <String>[
              readAt(mapped['wrong1']),
              readAt(mapped['wrong2']),
              readAt(mapped['wrong3']),
            ],
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
}
