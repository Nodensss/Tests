import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:quiz_trainer_flutter/services/excel_parser_service.dart';

void main() {
  group('ExcelParserService', () {
    test('maps wrong answer columns separately from correct answer', () async {
      final excel = Excel.createExcel();
      final sheet = excel[excel.getDefaultSheet() ?? 'Sheet1'];

      sheet.appendRow(<CellValue>[
        TextCellValue('ВОПРОС'),
        TextCellValue('Правильный ответ'),
        TextCellValue('Неправильный ответ 1'),
        TextCellValue('Неправильный ответ 2'),
        TextCellValue('Неправильный ответ 3'),
      ]);
      sheet.appendRow(<CellValue>[
        TextCellValue('Какой полимер является монодисперсным?'),
        TextCellValue('Белок'),
        TextCellValue('Полипропилен'),
        TextCellValue('Сополимер этилена и винилацетата'),
        TextCellValue('Полиэтилен высокого давления'),
      ]);

      final encoded = excel.encode();
      expect(encoded, isNotNull);

      final parser = ExcelParserService();
      final result = await parser.parse(
        bytes: Uint8List.fromList(encoded!),
        sourceFile: 'test.xlsx',
      );

      expect(result.questions.length, 1);
      final question = result.questions.first;
      expect(question.correctAnswer, 'Белок');
      expect(question.wrongAnswers, <String>[
        'Полипропилен',
        'Сополимер этилена и винилацетата',
        'Полиэтилен высокого давления',
      ]);
    });
  });
}
