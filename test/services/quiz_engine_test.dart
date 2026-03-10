import 'package:flutter_test/flutter_test.dart';

import 'package:quiz_trainer_flutter/models/question.dart';
import 'package:quiz_trainer_flutter/services/database_service.dart';
import 'package:quiz_trainer_flutter/services/quiz_engine.dart';

void main() {
  group('QuizEngine.buildOptions', () {
    test('fills missing options from fallback pool', () {
      final engine = QuizEngine(databaseService: DatabaseService.instance);
      const current = Question(
        questionText: 'Какой полимер является монодисперсным?',
        correctAnswer: 'Белок',
        wrongAnswers: <String>['Белок', 'Белок', 'Белок'],
      );
      const pool = <Question>[
        Question(
          questionText: 'Q2',
          correctAnswer: 'Полипропилен',
          wrongAnswers: <String>['Полиэтилен', '', ''],
        ),
        Question(
          questionText: 'Q3',
          correctAnswer: 'Сополимер этилена и винилацетата',
          wrongAnswers: <String>['Полистирол', '', ''],
        ),
      ];

      final options = engine.buildOptions(current, fallbackPool: pool);

      expect(options, isNotEmpty);
      expect(options.toSet().length, 4);
      expect(options, contains('Белок'));
      expect(options.any((value) => value.trim().isEmpty), isFalse);
    });

    test('evaluates multi-select answers by exact set equality', () {
      final engine = QuizEngine(databaseService: DatabaseService.instance);
      const current = Question(
        questionText: 'Какие функции доступны? (2 правильных ответа)',
        correctAnswer: 'Сканировать NFC\nФиксировать несоответствие',
        correctAnswers: <String>[
          'Сканировать NFC',
          'Фиксировать несоответствие',
        ],
        wrongAnswers: <String>['Удалять базу', 'Отключать сервер', ''],
      );

      expect(
        engine.evaluateSelectedOptions(current, <String>[
          'Фиксировать несоответствие',
          'Сканировать NFC',
        ]),
        isTrue,
      );
      expect(
        engine.evaluateSelectedOptions(current, <String>[
          'Сканировать NFC',
        ]),
        isFalse,
      );
      expect(
        engine.evaluateSelectedOptions(current, <String>[
          'Сканировать NFC',
          'Удалять базу',
        ]),
        isFalse,
      );
    });
  });
}
