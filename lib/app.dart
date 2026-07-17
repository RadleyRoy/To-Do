import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/providers.dart';
import 'features/calendar/calendar_screen.dart';
import 'features/lists/lists_home_screen.dart';
import 'features/settings/settings_screen.dart';
import 'features/tasks/task_editor_sheet.dart';

class TaskleyApp extends ConsumerWidget {
  const TaskleyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    const seed = Color(0xFF3D6BFF);
    return MaterialApp(
      title: 'Taskley',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: seed),
      ),
      darkTheme: ThemeData(
        colorScheme:
            ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.dark),
      ),
      themeMode: ThemeMode.system,
      home: const HomeShell(),
    );
  }
}

class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    final notifications = ref.read(notificationServiceProvider);
    notifications.onTapTask = _openTask;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      notifications.requestPermissions();
      final launchTaskId = notifications.takeLaunchTaskId();
      if (launchTaskId != null) _openTask(launchTaskId);
    });
  }

  Future<void> _openTask(int taskId) async {
    final task = await ref.read(databaseProvider).getTask(taskId);
    if (task != null && mounted) {
      await showTaskEditor(context, task: task);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _tab,
        children: const [
          ListsHomeScreen(),
          CalendarScreen(),
          SettingsScreen(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.checklist_outlined),
              selectedIcon: Icon(Icons.checklist),
              label: 'Lists'),
          NavigationDestination(
              icon: Icon(Icons.calendar_month_outlined),
              selectedIcon: Icon(Icons.calendar_month),
              label: 'Calendar'),
          NavigationDestination(
              icon: Icon(Icons.settings_outlined),
              selectedIcon: Icon(Icons.settings),
              label: 'Settings'),
        ],
      ),
    );
  }
}
