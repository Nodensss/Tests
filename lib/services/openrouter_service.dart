import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import '../models/question.dart';
import 'ai_progress.dart';
import 'competency_service.dart';
import 'database_service.dart';

class OpenRouterService {
  OpenRouterService({
    required this.databaseService,
    this.apiKey = '',
    this.modelName = 'openrouter/free',
    this.maxRetries = 3,
  });

  final DatabaseService databaseService;
  final String apiKey;
  final String modelName;
  final int maxRetries;
  static const String _categorizerVersion = 'v5';
  static const String _explanationVersion = 'v3';
  static const String _memoryTipVersion = 'v2';
  static const String _studyPlanVersion = 'v2';
  static const String defaultExplanationSystemPrompt =
      'Ты объясняешь экзаменационные ответы просто и коротко. '
      'Отвечай только на русском языке.';
  static const String defaultExplanationUserPromptTemplate = '''
Объясни, почему правильный ответ верный.
Добавь короткую мнемоническую подсказку.
Пиши только на русском языке. Английский язык не используй.

Вопрос: {question}
Правильный ответ: {correct_answer}
''';
  static const String defaultMemoryTipSystemPrompt =
      'Ты тренер по запоминанию технических вопросов. '
      'Отвечай только на русском языке.';
  static const String defaultMemoryTipUserPromptTemplate = '''
Сделай краткую памятку, чтобы человек запомнил правильный ответ.
Формат:
1) Ключевая идея (1-2 предложения)
2) Ассоциация/мнемоника (1 короткая фраза)
3) Мини-проверка себя (1 вопрос для самопроверки)
Пиши только на русском языке. Английский язык не используй.

Вопрос: {question}
Правильный ответ: {correct_answer}
''';
  final CompetencyService _competencyService = CompetencyService();
  String? _lastError;
  List<String>? _cachedAvailableModels;
  DateTime? _cachedAvailableModelsAt;

  bool get enabled => apiKey.trim().isNotEmpty;
  String? get lastError => _lastError;

  String _cacheKey(String type, Object payload) {
    final raw = jsonEncode(payload);
    final digest = sha256.convert(utf8.encode(raw)).toString();
    return '$type:$digest';
  }

  String _renderPromptTemplate({
    required String template,
    required String question,
    required String correctAnswer,
    String internetContext = '',
  }) {
    final usesQuestion = template.contains('{question}');
    final usesAnswer = template.contains('{correct_answer}');
    final usesInternet = template.contains('{internet_context}');
    var rendered = template
        .replaceAll('{question}', question)
        .replaceAll('{correct_answer}', correctAnswer)
        .replaceAll('{internet_context}', internetContext.trim());
    if (!usesQuestion) {
      rendered = '$rendered\n\nВопрос: $question';
    }
    if (!usesAnswer) {
      rendered = '$rendered\nПравильный ответ: $correctAnswer';
    }
    if (!usesInternet && internetContext.trim().isNotEmpty) {
      rendered =
          '$rendered\n\nКонтекст из интернета (проверьте факты по источникам):\n$internetContext';
    }
    return rendered;
  }

  Future<String?> _request(
    String systemPrompt,
    String userPrompt, {
    double temperature = 0.2,
    Duration timeout = const Duration(seconds: 70),
    int? maxTokens,
  }) async {
    _lastError = null;
    if (!enabled) {
      return null;
    }

    Object? lastError;
    final modelsToTry = <String>[
      modelName,
      if (modelName != 'openrouter/free') 'openrouter/free',
      if (modelName != 'openrouter/auto') 'openrouter/auto',
      'meta-llama/llama-3.1-8b-instruct:free',
      'google/gemma-2-9b-it:free',
      'mistralai/mistral-7b-instruct:free',
    ];
    var fetchedDynamicModels = false;
    for (var attempt = 1; attempt <= maxRetries; attempt++) {
      for (var modelIndex = 0; modelIndex < modelsToTry.length; modelIndex++) {
        final model = modelsToTry[modelIndex];
        try {
          final response = await http
              .post(
                Uri.parse('https://openrouter.ai/api/v1/chat/completions'),
                headers: <String, String>{
                  'Authorization': 'Bearer ${apiKey.trim()}',
                  'Content-Type': 'application/json',
                  'Accept': 'application/json',
                  'HTTP-Referer': 'https://localhost',
                  'X-Title': 'Quiz Trainer Flutter',
                },
                body: jsonEncode(<String, Object>{
                  'model': model,
                  'temperature': temperature,
                  if (maxTokens != null) 'max_tokens': maxTokens,
                  'messages': <Map<String, String>>[
                    <String, String>{'role': 'system', 'content': systemPrompt},
                    <String, String>{'role': 'user', 'content': userPrompt},
                  ],
                }),
              )
              .timeout(timeout);

          if (response.statusCode < 200 || response.statusCode >= 300) {
            lastError = _buildHttpError(response.statusCode, response.body);
            final canTryNextModel =
                response.statusCode == 403 ||
                response.statusCode == 404 ||
                response.statusCode == 422;
            if (canTryNextModel && !fetchedDynamicModels) {
              fetchedDynamicModels = true;
              final dynamicModels = await _fetchAvailableModels();
              for (final dynamicModel in dynamicModels) {
                if (!modelsToTry.contains(dynamicModel)) {
                  modelsToTry.add(dynamicModel);
                }
              }
            }
            if (canTryNextModel && model != modelsToTry.last) {
              continue;
            }
            await Future<void>.delayed(Duration(seconds: attempt * 2));
            continue;
          }

          final decoded = jsonDecode(response.body);
          if (decoded is! Map) {
            lastError = 'Invalid JSON envelope';
            continue;
          }
          final choices = decoded['choices'];
          if (choices is! List || choices.isEmpty) {
            lastError = 'No choices';
            continue;
          }
          final first = choices.first;
          if (first is! Map) {
            lastError = 'Invalid choice';
            continue;
          }
          final message = first['message'];
          if (message is! Map) {
            lastError = 'Invalid message';
            continue;
          }
          final content = message['content']?.toString().trim();
          if (content != null && content.isNotEmpty) {
            return content;
          }
          lastError = 'Empty content';
        } catch (e) {
          lastError = e;
          await Future<void>.delayed(Duration(seconds: attempt * 2));
        }
      }
    }

    if (lastError != null) {
      _lastError = lastError.toString();
      return null;
    }
    return null;
  }

  Future<List<String>> _fetchAvailableModels() async {
    if (!enabled) {
      return const <String>[];
    }
    final now = DateTime.now();
    if (_cachedAvailableModels != null &&
        _cachedAvailableModelsAt != null &&
        now.difference(_cachedAvailableModelsAt!).inMinutes < 15) {
      return _cachedAvailableModels!;
    }

    try {
      final response = await http
          .get(
            Uri.parse('https://openrouter.ai/api/v1/models'),
            headers: <String, String>{
              'Authorization': 'Bearer ${apiKey.trim()}',
              'Content-Type': 'application/json',
              'Accept': 'application/json',
              'HTTP-Referer': 'https://localhost',
              'X-Title': 'Quiz Trainer Flutter',
            },
          )
          .timeout(const Duration(seconds: 30));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return const <String>[];
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! Map) {
        return const <String>[];
      }
      final data = decoded['data'];
      if (data is! List) {
        return const <String>[];
      }
      final models = data
          .whereType<Map>()
          .map((item) => (item['id'] ?? '').toString().trim())
          .where((id) => id.isNotEmpty)
          .where((id) => id.endsWith(':free') || id.startsWith('openrouter/'))
          .where((id) => !id.contains('whisper'))
          .where((id) => !id.contains('guard'))
          .toList(growable: false);
      _cachedAvailableModels = models;
      _cachedAvailableModelsAt = now;
      return models;
    } catch (_) {
      return const <String>[];
    }
  }

  String _buildHttpError(int statusCode, String body) {
    var detail = '';
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map) {
        final error = decoded['error'];
        if (error is Map) {
          detail = (error['message'] ?? '').toString().trim();
          if (detail.isEmpty) {
            detail = (error['code'] ?? '').toString().trim();
          }
        }
      }
    } catch (_) {
      detail = body.trim();
    }
    if (detail.length > 220) {
      detail = '${detail.substring(0, 220)}...';
    }
    if (detail.isEmpty && statusCode == 403) {
      return 'HTTP 403: Forbidden. Проверьте права ключа в OpenRouter и доступность модели.';
    }
    return detail.isEmpty ? 'HTTP $statusCode' : 'HTTP $statusCode: $detail';
  }

  bool _isFallbackPayload(String payload) {
    final text = payload.toLowerCase();
    return text.contains('добавьте openrouter api key') ||
        text.contains('не удалось получить ответ openrouter');
  }

  List<Map<String, dynamic>> _extractJsonList(String raw) {
    var text = raw.trim();
    if (text.startsWith('```')) {
      text = text.replaceFirst(RegExp(r'^```json', caseSensitive: false), '');
      text = text.replaceFirst(RegExp(r'^```'), '');
      text = text.replaceAll('```', '').trim();
    }

    final start = text.indexOf('[');
    final end = text.lastIndexOf(']');
    if (start >= 0 && end > start) {
      text = text.substring(start, end + 1);
    }

    final decoded = jsonDecode(text);
    if (decoded is Map && decoded['items'] is List) {
      final list = decoded['items'] as List;
      return list
          .whereType<Map>()
          .map(
            (item) => item.map(
              (key, value) => MapEntry(key.toString(), value as dynamic),
            ),
          )
          .toList(growable: false);
    }
    if (decoded is! List) {
      return const <Map<String, dynamic>>[];
    }
    return decoded
        .whereType<Map>()
        .map(
          (item) => item.map(
            (key, value) => MapEntry(key.toString(), value as dynamic),
          ),
        )
        .toList(growable: false);
  }

  bool _containsAny(String text, List<String> markers) {
    for (final marker in markers) {
      if (text.contains(marker)) {
        return true;
      }
    }
    return false;
  }

  Map<String, dynamic> _fallbackCategory(String questionText) {
    final text = questionText.toLowerCase();

    if (_containsAny(text, <String>[
      'манометр',
      'кипиа',
      'датчик',
      'измеритель',
      'сигнализац',
      'расходомер',
      'термометр',
      'пдк',
      'давлен',
      'температур',
    ])) {
      return <String, dynamic>{
        'category': 'КИПиА и измерения',
        'subcategory': 'Датчики, показания и нормы',
        'difficulty': 3,
        'keywords': <String>['кипиа', 'давление', 'температура'],
      };
    }
    if (_containsAny(text, <String>[
      'насос',
      'кавитац',
      'всас',
      'нагнетан',
      'бустер',
      'подпор',
    ])) {
      return <String, dynamic>{
        'category': 'Насосное оборудование',
        'subcategory': 'Эксплуатация и неисправности',
        'difficulty': 3,
        'keywords': <String>['насос', 'нагнетание', 'кавитация'],
      };
    }
    if (_containsAny(text, <String>[
      'компресс',
      'ступен',
      'сжати',
      'нагнетател',
      'всасыван',
      'компрессор',
    ])) {
      return <String, dynamic>{
        'category': 'Компрессорное оборудование',
        'subcategory': 'Режимы и защита',
        'difficulty': 3,
        'keywords': <String>['компрессор', 'ступень', 'давление'],
      };
    }
    if (_containsAny(text, <String>[
      'реактор',
      'каскад',
      'инициатор',
      'этилен',
      'полиэтилен',
      'экструдер',
      'полимер',
    ])) {
      return <String, dynamic>{
        'category': 'Полимеризация и реактор',
        'subcategory': 'Технологический процесс',
        'difficulty': 4,
        'keywords': <String>['реактор', 'полиэтилен', 'инициатор'],
      };
    }
    if (_containsAny(text, <String>[
      'клапан',
      'задвижк',
      'сппк',
      'арматур',
      'трубопровод',
      'линия',
      'линии',
    ])) {
      return <String, dynamic>{
        'category': 'Трубопроводы и арматура',
        'subcategory': 'Клапаны и линии',
        'difficulty': 3,
        'keywords': <String>['клапан', 'линия', 'арматура'],
      };
    }
    if (_containsAny(text, <String>[
      'авар',
      'газоопас',
      'инструктаж',
      'наряд',
      'допуск',
      'сиз',
      'плакат',
      'безопасн',
      'ремонт',
      'эксплуатац',
    ])) {
      return <String, dynamic>{
        'category': 'Охрана труда и ПБ',
        'subcategory': 'Инструктаж и допуски',
        'difficulty': 2,
        'keywords': <String>['безопасность', 'инструктаж', 'допуск'],
      };
    }
    return <String, dynamic>{
      'category': 'Общие технологические вопросы',
      'subcategory': 'Общие регламенты',
      'difficulty': 3,
      'keywords': <String>['технология', 'эксплуатация'],
    };
  }

  int _resolveBatchSize(int totalQuestions, int requestedBatchSize) {
    var effective = requestedBatchSize <= 0 ? 1 : requestedBatchSize;
    if (requestedBatchSize == 25) {
      if (totalQuestions >= 1200) {
        effective = 60;
      } else if (totalQuestions >= 700) {
        effective = 50;
      } else if (totalQuestions >= 300) {
        effective = 40;
      }
    }
    return effective.clamp(15, 80);
  }

  int _categorizationMaxTokensForBatch(int batchLength) {
    if (batchLength >= 60) {
      return 3200;
    }
    if (batchLength >= 40) {
      return 2600;
    }
    return 2000;
  }

  Future<List<Question>> categorizeQuestions(
    List<Question> questions, {
    int batchSize = 25,
    CategorizationProgressCallback? onProgress,
  }) async {
    if (questions.isEmpty) {
      return const <Question>[];
    }

    final result = <Question>[];
    final totalQuestions = questions.length;
    final effectiveBatchSize = _resolveBatchSize(totalQuestions, batchSize);
    final totalBatches = (totalQuestions / effectiveBatchSize).ceil();
    final competencyListText = CompetencyService.allCompetencies
        .map((item) => '- $item')
        .join('\n');

    onProgress?.call(
      CategorizationProgress(
        processedQuestions: 0,
        totalQuestions: totalQuestions,
        batchIndex: 0,
        totalBatches: totalBatches,
        stage: 'Подготовка батчей по $effectiveBatchSize вопросов',
        stageProgress: 0.0,
        currentBatchSize: effectiveBatchSize,
      ),
    );

    const systemPrompt = '''
Ты помогаешь категоризировать экзаменационные вопросы.
Отвечай строго JSON, без пояснений.
''';

    for (
      var offset = 0;
      offset < questions.length;
      offset += effectiveBatchSize
    ) {
      final batchIndex = (offset ~/ effectiveBatchSize) + 1;
      final batch = questions
          .skip(offset)
          .take(effectiveBatchSize)
          .toList(growable: false);
      onProgress?.call(
        CategorizationProgress(
          processedQuestions: result.length,
          totalQuestions: totalQuestions,
          batchIndex: batchIndex,
          totalBatches: totalBatches,
          stage: 'Батч $batchIndex/$totalBatches: проверка кэша',
          stageProgress: 0.05,
          currentBatchSize: batch.length,
        ),
      );

      final cacheKey = _cacheKey('categorize_openrouter', <String, Object>{
        'version': _categorizerVersion,
        'model': modelName,
        'questions': batch.map((q) => q.questionText).toList(growable: false),
      });

      List<Map<String, dynamic>> parsed = const <Map<String, dynamic>>[];
      var cacheHit = false;
      final cache = await databaseService.getCache(cacheKey);
      if (cache != null) {
        try {
          parsed = (jsonDecode(cache) as List)
              .whereType<Map>()
              .map((item) => item.map((k, v) => MapEntry(k.toString(), v)))
              .toList(growable: false);
          cacheHit = parsed.isNotEmpty;
        } catch (_) {
          parsed = const <Map<String, dynamic>>[];
          cacheHit = false;
        }
      }

      if (!cacheHit && enabled) {
        onProgress?.call(
          CategorizationProgress(
            processedQuestions: result.length,
            totalQuestions: totalQuestions,
            batchIndex: batchIndex,
            totalBatches: totalBatches,
            stage: 'Батч $batchIndex/$totalBatches: запрос к OpenRouter',
            stageProgress: 0.35,
            currentBatchSize: batch.length,
          ),
        );

        final listText = batch
            .asMap()
            .entries
            .map((e) => '${e.key}. ${e.value.questionText}')
            .join('\n');
        final userPrompt =
            '''
Категоризируй вопросы. Верни только JSON-массив.
Требования:
- category: конкретная тема 2-5 слов, не используй "Общее" или "Разное".
- subcategory: более узкая тема.
- competency: строго одно значение из списка компетенций.
- difficulty: целое 1..5.
- keywords: 2-3 слова.

Список компетенций:
$competencyListText

Формат:
[
  {
    "question_index": 0,
    "category": "...",
    "subcategory": "...",
    "competency": "...",
    "difficulty": 3,
    "keywords": ["...", "..."]
  }
]

Вопросы:
$listText
''';
        final response = await _request(
          systemPrompt,
          userPrompt,
          temperature: 0.2,
          timeout: const Duration(seconds: 45),
          maxTokens: _categorizationMaxTokensForBatch(batch.length),
        );
        if (response != null) {
          try {
            parsed = _extractJsonList(response);
          } catch (_) {
            parsed = const <Map<String, dynamic>>[];
          }
        }
        if (parsed.isNotEmpty) {
          await databaseService.setCache(
            cacheKey: cacheKey,
            cacheType: 'categorization_openrouter',
            payload: jsonEncode(parsed),
          );
        }
      } else if (cacheHit) {
        onProgress?.call(
          CategorizationProgress(
            processedQuestions: result.length,
            totalQuestions: totalQuestions,
            batchIndex: batchIndex,
            totalBatches: totalBatches,
            stage: 'Батч $batchIndex/$totalBatches: кэш найден',
            stageProgress: 0.75,
            currentBatchSize: batch.length,
          ),
        );
      } else {
        onProgress?.call(
          CategorizationProgress(
            processedQuestions: result.length,
            totalQuestions: totalQuestions,
            batchIndex: batchIndex,
            totalBatches: totalBatches,
            stage: 'Батч $batchIndex/$totalBatches: локальная категоризация',
            stageProgress: 0.75,
            currentBatchSize: batch.length,
          ),
        );
      }

      final byIndex = <int, Map<String, dynamic>>{};
      for (final row in parsed) {
        final index = int.tryParse('${row['question_index'] ?? ''}') ?? -1;
        if (index >= 0) {
          byIndex[index] = row;
        }
      }

      for (var i = 0; i < batch.length; i++) {
        final question = batch[i];
        final data = byIndex[i] ?? _fallbackCategory(question.questionText);
        final keywordsRaw = data['keywords'];
        final keywords = <String>[
          if (keywordsRaw is List)
            ...keywordsRaw.map((item) => item.toString()).take(3),
        ];
        final difficulty = (int.tryParse('${data['difficulty'] ?? 3}') ?? 3)
            .clamp(1, 5);
        final category = (data['category'] ?? '').toString().trim();
        final subcategory = (data['subcategory'] ?? '').toString().trim();
        final competency = _competencyService.resolveCompetency(
          rawCompetency: data['competency']?.toString(),
          questionText: question.questionText,
          category: category,
          subcategory: subcategory,
        );
        result.add(
          question.copyWith(
            competency: competency,
            category: category.isEmpty ? competency : category,
            subcategory: subcategory.isEmpty ? 'Без подкатегории' : subcategory,
            difficulty: difficulty,
            keywords: keywords,
          ),
        );
      }

      onProgress?.call(
        CategorizationProgress(
          processedQuestions: result.length,
          totalQuestions: totalQuestions,
          batchIndex: batchIndex,
          totalBatches: totalBatches,
          stage: 'Батч $batchIndex/$totalBatches: завершен',
          stageProgress: 1.0,
          currentBatchSize: batch.length,
        ),
      );
    }

    onProgress?.call(
      CategorizationProgress(
        processedQuestions: totalQuestions,
        totalQuestions: totalQuestions,
        batchIndex: totalBatches,
        totalBatches: totalBatches,
        stage: 'Категоризация завершена',
        stageProgress: 1.0,
        currentBatchSize: 0,
      ),
    );

    return result;
  }

  Future<String> generateExplanation({
    required int questionId,
    required String question,
    required String correctAnswer,
    String? systemPrompt,
    String? userPromptTemplate,
    String? internetContext,
  }) async {
    final resolvedSystemPrompt =
        (systemPrompt ?? defaultExplanationSystemPrompt).trim();
    final resolvedUserTemplate =
        (userPromptTemplate ?? defaultExplanationUserPromptTemplate).trim();
    final renderedUserPrompt = _renderPromptTemplate(
      template: resolvedUserTemplate,
      question: question,
      correctAnswer: correctAnswer,
      internetContext: internetContext ?? '',
    );

    final cacheKey = _cacheKey('explanation_openrouter', <String, Object>{
      'version': _explanationVersion,
      'model': modelName,
      'system_prompt': resolvedSystemPrompt,
      'user_prompt_template': resolvedUserTemplate,
      'internet_context': internetContext?.trim() ?? '',
      'question': question,
      'answer': correctAnswer,
    });
    final cached = await databaseService.getCache(cacheKey);
    if (cached != null &&
        cached.trim().isNotEmpty &&
        !_isFallbackPayload(cached)) {
      await databaseService.updateQuestionExplanation(
        questionId: questionId,
        explanation: cached,
      );
      return cached;
    }

    String explanation = '';
    if (enabled) {
      explanation =
          (await _request(
            resolvedSystemPrompt,
            renderedUserPrompt,
            temperature: 0.35,
          )) ??
          '';
    }

    if (explanation.trim().isEmpty) {
      if (!enabled) {
        explanation =
            'Правильный ответ: $correctAnswer. Добавьте OpenRouter API key для расширенного объяснения.';
      } else {
        final reason = (lastError ?? '').trim();
        explanation = reason.isEmpty
            ? 'Не удалось получить ответ OpenRouter. Проверьте интернет, лимиты и модель.'
            : 'Ошибка OpenRouter: $reason';
      }
      await databaseService.updateQuestionExplanation(
        questionId: questionId,
        explanation: explanation,
      );
      return explanation;
    }

    await databaseService.setCache(
      cacheKey: cacheKey,
      cacheType: 'explanation_openrouter',
      payload: explanation,
    );
    await databaseService.updateQuestionExplanation(
      questionId: questionId,
      explanation: explanation,
    );
    return explanation;
  }

  Future<String> suggestStudyPlan(Map<String, Object> stats) async {
    final cacheKey = _cacheKey('study_plan_openrouter', <String, Object>{
      'version': _studyPlanVersion,
      'model': modelName,
      'stats': stats,
    });
    final cached = await databaseService.getCache(cacheKey);
    if (cached != null && cached.trim().isNotEmpty) {
      return cached;
    }

    String plan = '';
    if (enabled) {
      plan =
          (await _request('Ты методист по обучению.', '''
Составь план обучения на 7 дней, 5-7 коротких пунктов.

Статистика:
${jsonEncode(stats)}
''', temperature: 0.35)) ??
          '';
    }

    if (plan.trim().isEmpty) {
      plan = '''
1. Ежедневно решайте 20 вопросов.
2. Начинайте с режима Review, затем переходите в Quiz.
3. Повторяйте сложные категории в отдельной сессии Category Drill.
4. После ошибок открывайте объяснение и возвращайтесь к вопросу на следующий день.
5. Раз в 3 дня сверяйте прогресс в разделе Analytics.
''';
    }

    await databaseService.setCache(
      cacheKey: cacheKey,
      cacheType: 'study_plan_openrouter',
      payload: plan,
    );
    return plan;
  }

  Future<String> generateMemoryTip({
    required int questionId,
    required String question,
    required String correctAnswer,
    String? systemPrompt,
    String? userPromptTemplate,
    String? internetContext,
  }) async {
    final resolvedSystemPrompt = (systemPrompt ?? defaultMemoryTipSystemPrompt)
        .trim();
    final resolvedUserTemplate =
        (userPromptTemplate ?? defaultMemoryTipUserPromptTemplate).trim();
    final renderedUserPrompt = _renderPromptTemplate(
      template: resolvedUserTemplate,
      question: question,
      correctAnswer: correctAnswer,
      internetContext: internetContext ?? '',
    );

    final cacheKey = _cacheKey('memory_tip_openrouter', <String, Object>{
      'version': _memoryTipVersion,
      'model': modelName,
      'system_prompt': resolvedSystemPrompt,
      'user_prompt_template': resolvedUserTemplate,
      'internet_context': internetContext?.trim() ?? '',
      'question_id': questionId,
      'question': question,
      'answer': correctAnswer,
    });
    final cached = await databaseService.getCache(cacheKey);
    if (cached != null &&
        cached.trim().isNotEmpty &&
        !_isFallbackPayload(cached)) {
      return cached;
    }

    String tip = '';
    if (enabled) {
      tip =
          (await _request(
            resolvedSystemPrompt,
            renderedUserPrompt,
            temperature: 0.35,
          )) ??
          '';
    }

    if (tip.trim().isEmpty) {
      if (!enabled) {
        tip =
            'Ключ: выделите в вопросе опорное слово и свяжите его с ответом "$correctAnswer". Добавьте OpenRouter API key для AI-памятки.';
      } else {
        final reason = (lastError ?? '').trim();
        tip = reason.isEmpty
            ? 'Не удалось получить памятку. Повторите запрос позже.'
            : 'Ошибка OpenRouter: $reason';
      }
    }

    await databaseService.setCache(
      cacheKey: cacheKey,
      cacheType: 'memory_tip_openrouter',
      payload: tip,
    );
    return tip;
  }
}
