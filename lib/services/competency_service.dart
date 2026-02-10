class CompetencyService {
  static const String generalCompetency = 'Инструкция общая (уточнить компетенцию)';

  static const List<String> competencyCatalog = <String>[
    'Знание Пульта управления технологическим процессом к 430 (ВГНД)',
    'Узел приготовления реагента НАЛКО',
    'Узел Реакторного блока',
    'Узел ВГВД',
    'Узел холодильной установки',
    'Узел Приготовления горячей воды и подачи ее в зоны реакции',
    'Узел приема пара',
    'Узел АПТВ',
    'Узел инициаторной станции',
    'Узел приёма пара и энергоресурсов',
    'Узел сушки к.421/1, 422/1',
    'Узел пневмотранспорта',
    'Узел гидротранспорта к.421/1, 422/1',
    'Узел мастер-батча',
    'Узел основой экструзионной линии',
    'Узел компримирования этилена (в ЗО)',
    'Узел первичной грануляции (в ЗО)',
    'Склад ПАЛ',
    'Узел теплой воды (т.409)',
    'Склад масел, перекиси',
    'Узел ПАЛ',
    'Знание Пульта управления технологическим процессом к430 (грануляция)',
    'Система пневмотранспортирования (Машинисты гранулирования пластмасс УПиДПП, КиПС (Отделение подготовки полиэтилена т.410))',
    'Узел полимеризации (ВГНД)',
    'Узел приготовления растворов рН',
    'Узел теплой воды, теплоузел',
  ];

  static const List<String> allCompetencies = <String>[
    ...competencyCatalog,
    generalCompetency,
  ];

  bool hasCompetency(String? value) {
    if (value == null || value.trim().isEmpty) {
      return false;
    }
    return _matchByName(value.trim()) != null;
  }

  String resolveCompetency({
    String? rawCompetency,
    required String questionText,
    String? category,
    String? subcategory,
  }) {
    final raw = rawCompetency?.trim() ?? '';
    if (raw.isNotEmpty) {
      final matched = _matchByName(raw);
      if (matched != null) {
        return matched;
      }
    }

    final text = '$questionText ${category ?? ''} ${subcategory ?? ''}'.trim();
    final byRules = _ruleBased(text.toLowerCase());
    if (byRules != null) {
      return byRules;
    }
    return generalCompetency;
  }

  String? _matchByName(String raw) {
    if (allCompetencies.contains(raw)) {
      return raw;
    }
    final normalizedRaw = _normalize(raw);
    for (final competency in allCompetencies) {
      final norm = _normalize(competency);
      if (normalizedRaw == norm ||
          normalizedRaw.contains(norm) ||
          norm.contains(normalizedRaw)) {
        return competency;
      }
    }

    var bestScore = 0.0;
    String? best;
    for (final competency in allCompetencies) {
      final score = _tokenScore(normalizedRaw, _normalize(competency));
      if (score > bestScore) {
        bestScore = score;
        best = competency;
      }
    }
    if (best != null && bestScore >= 0.6) {
      return best;
    }
    return null;
  }

  bool _containsAny(String text, List<String> markers) {
    for (final marker in markers) {
      if (text.contains(marker)) {
        return true;
      }
    }
    return false;
  }

  String? _ruleBased(String text) {
    if (_containsAny(text, <String>[
      'пульт',
      'к 430',
      'к430',
      'вгнд',
    ])) {
      if (_containsAny(text, <String>['грануляц', 'т.410', 'кипс', 'упидпп'])) {
        return 'Знание Пульта управления технологическим процессом к430 (грануляция)';
      }
      return 'Знание Пульта управления технологическим процессом к 430 (ВГНД)';
    }

    if (_containsAny(text, <String>['налко', 'реагент'])) {
      return 'Узел приготовления реагента НАЛКО';
    }

    if (_containsAny(text, <String>['вгвд'])) {
      return 'Узел ВГВД';
    }

    if (_containsAny(text, <String>['холодиль'])) {
      return 'Узел холодильной установки';
    }

    if (_containsAny(text, <String>['горяч', 'подачи', 'зоны реакции']) &&
        _containsAny(text, <String>['вод'])) {
      return 'Узел Приготовления горячей воды и подачи ее в зоны реакции';
    }

    if (_containsAny(text, <String>['теплой воды', 'т.409'])) {
      return 'Узел теплой воды (т.409)';
    }
    if (_containsAny(text, <String>['теплоузел'])) {
      return 'Узел теплой воды, теплоузел';
    }

    if (_containsAny(text, <String>['пар', 'энергоресурс'])) {
      if (_containsAny(text, <String>['энергоресурс', 'приёма пара'])) {
        return 'Узел приёма пара и энергоресурсов';
      }
      return 'Узел приема пара';
    }

    if (_containsAny(text, <String>['аптв', 'пожар', 'пожаротуш'])) {
      return 'Узел АПТВ';
    }

    if (_containsAny(text, <String>['инициатор'])) {
      return 'Узел инициаторной станции';
    }
    if (_containsAny(text, <String>['раствор', 'рн', 'ph'])) {
      return 'Узел приготовления растворов рН';
    }

    if (_containsAny(text, <String>['сушк', '421/1', '422/1'])) {
      return 'Узел сушки к.421/1, 422/1';
    }

    if (_containsAny(text, <String>['пневмотранспортирования', 'упидпп', 'кипс', 'т.410'])) {
      return 'Система пневмотранспортирования (Машинисты гранулирования пластмасс УПиДПП, КиПС (Отделение подготовки полиэтилена т.410))';
    }
    if (_containsAny(text, <String>['пневмотранспорт'])) {
      return 'Узел пневмотранспорта';
    }
    if (_containsAny(text, <String>['гидротранспорт'])) {
      return 'Узел гидротранспорта к.421/1, 422/1';
    }

    if (_containsAny(text, <String>['мастер-батч', 'мастер батч'])) {
      return 'Узел мастер-батча';
    }
    if (_containsAny(text, <String>['экструдер', 'экструзион'])) {
      return 'Узел основой экструзионной линии';
    }

    if (_containsAny(text, <String>['компримирован', 'компресс'])) {
      return 'Узел компримирования этилена (в ЗО)';
    }
    if (_containsAny(text, <String>['грануляц', 'первичной грануляции'])) {
      return 'Узел первичной грануляции (в ЗО)';
    }

    if (_containsAny(text, <String>['полиэтилен', 'полимеризац'])) {
      return 'Узел полимеризации (ВГНД)';
    }
    if (_containsAny(text, <String>['реактор', 'каскад'])) {
      return 'Узел Реакторного блока';
    }

    if (_containsAny(text, <String>['масл', 'перекис'])) {
      return 'Склад масел, перекиси';
    }
    if (_containsAny(text, <String>['склад', 'пал']) &&
        !_containsAny(text, <String>['узел'])) {
      return 'Склад ПАЛ';
    }
    if (_containsAny(text, <String>['пал'])) {
      return 'Узел ПАЛ';
    }

    return null;
  }

  String _normalize(String value) {
    final lowered = value.toLowerCase().trim();
    final cleaned = lowered.replaceAll(RegExp(r'[^a-zа-я0-9 ]', unicode: true), ' ');
    return cleaned.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  double _tokenScore(String a, String b) {
    if (a.isEmpty || b.isEmpty) {
      return 0;
    }
    final aTokens = a.split(' ').where((item) => item.isNotEmpty).toSet();
    final bTokens = b.split(' ').where((item) => item.isNotEmpty).toSet();
    if (aTokens.isEmpty || bTokens.isEmpty) {
      return 0;
    }
    final intersection = aTokens.intersection(bTokens).length.toDouble();
    final union = aTokens.union(bTokens).length.toDouble();
    return union == 0 ? 0 : intersection / union;
  }
}
