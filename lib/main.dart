import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';

import 'screens/analytics_screen.dart';
import 'screens/hard_questions_screen.dart';
import 'screens/library_screen.dart';
import 'screens/study_screen.dart';
import 'screens/upload_screen.dart';
import 'services/openrouter_service.dart';
import 'state/app_state.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (kIsWeb) {
    databaseFactory = databaseFactoryFfiWeb;
  } else if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  runApp(const QuizTrainerApp());
}

class QuizTrainerApp extends StatelessWidget {
  const QuizTrainerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<AppState>(
      create: (_) => AppState()..initialize(),
      child: MaterialApp(
        title: 'Quiz Trainer',
        debugShowCheckedModeBanner: false,
        themeMode: ThemeMode.dark,
        darkTheme: ThemeData(
          brightness: Brightness.dark,
          colorScheme: const ColorScheme.dark(
            primary: Color(0xFFFF6B6B),
            secondary: Color(0xFF7AD3FF),
            surface: Color(0xFF1C1E24),
          ),
          scaffoldBackgroundColor: const Color(0xFF0E1117),
          useMaterial3: true,
        ),
        home: const HomeShell(),
      ),
    );
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _currentIndex = 0;

  static const _titles = <String>[
    'Upload',
    'Study',
    'Analytics',
    'Hard',
    'Library',
  ];

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final screens = <Widget>[
      const UploadScreen(),
      const StudyScreen(),
      const AnalyticsScreen(),
      const HardQuestionsScreen(),
      const LibraryScreen(),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text('Quiz Trainer · ${_titles[_currentIndex]}'),
        actions: <Widget>[
          IconButton(
            tooltip: 'AI provider and keys',
            onPressed: () => _showApiKeyDialog(context, appState),
            icon: const Icon(Icons.key),
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          _DashboardStrip(appState: appState),
          Expanded(child: screens[_currentIndex]),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        destinations: const <NavigationDestination>[
          NavigationDestination(
            icon: Icon(Icons.upload_file_outlined),
            selectedIcon: Icon(Icons.upload_file),
            label: 'Upload',
          ),
          NavigationDestination(
            icon: Icon(Icons.school_outlined),
            selectedIcon: Icon(Icons.school),
            label: 'Study',
          ),
          NavigationDestination(
            icon: Icon(Icons.analytics_outlined),
            selectedIcon: Icon(Icons.analytics),
            label: 'Analytics',
          ),
          NavigationDestination(
            icon: Icon(Icons.bookmarks_outlined),
            selectedIcon: Icon(Icons.bookmarks),
            label: 'Hard',
          ),
          NavigationDestination(
            icon: Icon(Icons.library_books_outlined),
            selectedIcon: Icon(Icons.library_books),
            label: 'Library',
          ),
        ],
      ),
    );
  }

  Future<void> _showApiKeyDialog(
    BuildContext context,
    AppState appState,
  ) async {
    var provider = appState.aiProvider;
    var useInternetSearch = appState.aiUseInternetSearch;
    final openRouterController = TextEditingController(
      text: appState.openRouterApiKey,
    );
    final explanationPromptController = TextEditingController(
      text: appState.explanationPromptTemplate,
    );
    final memoryTipPromptController = TextEditingController(
      text: appState.memoryTipPromptTemplate,
    );

    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('AI settings'),
          content: SizedBox(
            width: 760,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  DropdownButtonFormField<AiProvider>(
                    initialValue: provider,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: 'Provider',
                    ),
                    items: AiProvider.values
                        .map(
                          (item) => DropdownMenuItem<AiProvider>(
                            value: item,
                            child: Text(item.label),
                          ),
                        )
                        .toList(growable: false),
                    onChanged: (value) {
                      if (value == null) {
                        return;
                      }
                      setDialogState(() {
                        provider = value;
                      });
                    },
                  ),
                  const SizedBox(height: 10),
                  if (provider == AiProvider.openrouter) ...<Widget>[
                    TextField(
                      controller: openRouterController,
                      obscureText: true,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        hintText: 'Paste OPENROUTER API key',
                        labelText: 'OpenRouter API key',
                      ),
                    ),
                  ],
                  if (provider == AiProvider.local) ...<Widget>[
                    Text(
                      'Локальный режим использует только правила без внешнего API.',
                      style: TextStyle(color: Colors.grey.shade300),
                    ),
                  ],
                  const SizedBox(height: 14),
                  Text(
                    'Промпты для AI',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Используйте плейсхолдеры: {question}, {correct_answer}, {internet_context}.',
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    value: useInternetSearch,
                    onChanged: (value) {
                      setDialogState(() {
                        useInternetSearch = value;
                      });
                    },
                    title: const Text('Использовать интернет-поиск для AI'),
                    subtitle: const Text(
                      'Перед объяснением добавляется контекст из веб-источников.',
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: explanationPromptController,
                    minLines: 4,
                    maxLines: 9,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: 'Промпт: Объяснить (AI)',
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: memoryTipPromptController,
                    minLines: 4,
                    maxLines: 10,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: 'Промпт: Как запомнить (AI)',
                    ),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () {
                      explanationPromptController.text = OpenRouterService
                          .defaultExplanationUserPromptTemplate;
                      memoryTipPromptController.text =
                          OpenRouterService.defaultMemoryTipUserPromptTemplate;
                    },
                    icon: const Icon(Icons.refresh),
                    label: const Text('Сбросить промпты по умолчанию'),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: <Widget>[
                      Chip(
                        label: Text('Current: ${appState.aiProvider.label}'),
                      ),
                      if (appState.openRouterApiKey.trim().isNotEmpty)
                        const Chip(label: Text('OpenRouter key set')),
                    ],
                  ),
                ],
              ),
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                await appState.updateAiSettings(
                  provider: provider,
                  openRouterKey: openRouterController.text,
                  explanationPrompt: explanationPromptController.text,
                  memoryTipPrompt: memoryTipPromptController.text,
                  useInternetSearch: useInternetSearch,
                );
                if (!context.mounted) {
                  return;
                }
                Navigator.of(context).pop();
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }
}

class _DashboardStrip extends StatelessWidget {
  const _DashboardStrip({required this.appState});

  final AppState appState;

  @override
  Widget build(BuildContext context) {
    final totalQuestions = appState.userStats['total_questions'] ?? 0;
    final accuracyPct = appState.userStats['accuracy_pct'] ?? 0;
    final streak = appState.userStats['streak'] ?? 0;
    final due = appState.dueReviewCount;

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: _MetricTile(
              title: 'Questions',
              value: '$totalQuestions',
              icon: Icons.help_outline,
            ),
          ),
          Expanded(
            child: _MetricTile(
              title: 'Accuracy',
              value: '${(accuracyPct as num).toStringAsFixed(1)}%',
              icon: Icons.check_circle_outline,
            ),
          ),
          Expanded(
            child: _MetricTile(
              title: 'Streak',
              value: '$streak',
              icon: Icons.local_fire_department_outlined,
            ),
          ),
          Expanded(
            child: _MetricTile(
              title: 'Review due',
              value: '$due',
              icon: Icons.refresh_outlined,
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({
    required this.title,
    required this.value,
    required this.icon,
  });

  final String title;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(icon, size: 18, color: Theme.of(context).colorScheme.secondary),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
        ),
        const SizedBox(height: 2),
        Text(
          title,
          style: TextStyle(fontSize: 12, color: Colors.grey.shade400),
        ),
      ],
    );
  }
}
