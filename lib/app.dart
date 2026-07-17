import 'package:drift/drift.dart' show TableUpdate, UpdateKind;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/notifications/notification_service.dart';
import 'core/providers.dart';
import 'features/calendar/calendar_screen.dart';
import 'features/lists/lists_home_screen.dart';
import 'features/settings/settings_screen.dart';
import 'features/tasks/snooze_sheet.dart';
import 'features/tasks/task_editor_sheet.dart';

class TaskleyApp extends ConsumerWidget {
  const TaskleyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Taskley brand violet — matches the launcher icon.
    const seed = Color(0xFF5D38F5);
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

class _HomeShellState extends ConsumerState<HomeShell>
    with WidgetsBindingObserver {
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final notifications = ref.read(notificationServiceProvider);
    notifications.onTapTask = _handleNotificationTap;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      notifications.requestPermissions();
      final launchTap = notifications.takeLaunchTap();
      if (launchTap != null) {
        _handleNotificationTap(launchTap.$1, launchTap.$2);
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // The notification background isolate may have completed tasks while
      // we were paused; force our streams to re-query.
      final db = ref.read(databaseProvider);
      db.notifyUpdates({
        TableUpdate.onTable(db.tasks, kind: UpdateKind.update),
        TableUpdate.onTable(db.completions, kind: UpdateKind.insert),
      });
      ref.read(homeWidgetServiceProvider).refresh(db);
    }
  }

  Future<void> _handleNotificationTap(int taskId, String? actionId) async {
    final task = await ref.read(databaseProvider).getTask(taskId);
    if (task == null || !mounted) return;
    if (actionId == kActionSnooze) {
      await showSnoozeSheet(context, ref, task);
    } else {
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
