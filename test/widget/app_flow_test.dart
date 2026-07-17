import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskley/app.dart';
import 'package:taskley/core/db/database.dart';
import 'package:taskley/core/notifications/notification_service.dart';
import 'package:taskley/core/providers.dart';
import 'package:taskley/core/recurrence/recurrence_engine.dart';
import 'package:taskley/core/widget/home_widget_service.dart';

/// Platform channels aren't available in widget tests, so every method that
/// would hit the notifications plugin becomes a no-op.
class FakeNotificationService extends NotificationService {
  final List<int> scheduled = [];
  final List<int> cancelled = [];

  @override
  Future<void> init() async {}

  @override
  Future<bool> requestPermissions() async => true;

  @override
  Future<bool> notificationsEnabled() async => true;

  @override
  Future<bool> exactAlarmsAllowed() async => true;

  @override
  Future<void> syncTaskReminder(Task task) async {
    if (task.hasAlarm && !task.isDone && task.dueAt != null) {
      scheduled.add(task.id);
    } else {
      cancelled.add(task.id);
    }
  }

  @override
  Future<void> cancelTaskReminder(int taskId) async => cancelled.add(taskId);

  @override
  Future<void> rescheduleAll(AppDatabase db) async {}
}

/// The real service awaits a db stream, which never resolves inside the
/// widget-test fake-async zone; the platform channel is unavailable anyway.
class FakeHomeWidgetService extends HomeWidgetService {
  @override
  Future<void> refresh(AppDatabase db) async {}
}

void main() {
  late AppDatabase db;
  late FakeNotificationService notifications;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    notifications = FakeNotificationService();
  });

  tearDown(() async {
    await db.close();
  });

  Future<void> pumpApp(WidgetTester tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        notificationServiceProvider.overrideWithValue(notifications),
        homeWidgetServiceProvider.overrideWithValue(FakeHomeWidgetService()),
      ],
      child: const TaskleyApp(),
    ));
    await tester.pumpAndSettle();
  }

  /// Drift schedules zero-duration timers when its stream queries get
  /// cancelled. Unmounting inside the test (instead of at automatic teardown)
  /// lets those timers fire, keeping the "no pending timers" invariant green.
  Future<void> unmountApp(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    // pump with a duration: zero-delay timers only fire when fake time
    // actually elapses.
    await tester.pump(const Duration(seconds: 1));
  }

  testWidgets('create a list, add an item, complete and un-complete it',
      (tester) async {
    await pumpApp(tester);

    // Create the list through the FAB menu.
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text('New list'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'Groceries');
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();
    expect(find.text('Groceries'), findsOneWidget);

    // Open it and quick-add an item.
    await tester.tap(find.text('Groceries'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Buy milk');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.text('Buy milk'), findsOneWidget);

    // Complete it: moves under "Completed", undo snackbar appears.
    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();
    expect(find.textContaining('Completed (1)'), findsOneWidget);
    expect(find.textContaining('Completed "Buy milk"'), findsOneWidget);

    // Un-complete it again.
    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();
    expect(find.textContaining('Completed (1)'), findsNothing);

    await unmountApp(tester);
  });

  testWidgets('new task editor validates and saves a timed task',
      (tester) async {
    await pumpApp(tester);

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text('New task'));
    await tester.pumpAndSettle();

    // Saving without a title complains.
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Give the task a title'), findsOneWidget);

    // A titled task still needs a list or a date.
    await tester.enterText(
        find.widgetWithText(TextField, 'Title'), 'Car Service');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Pick a list or set a date'), findsOneWidget);

    // Add today's date via the date picker.
    await tester.tap(find.text('Add date'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    // Editor closed; task is in Today.
    expect(find.text('New task'), findsNothing);
    await tester.tap(find.text('Today'));
    await tester.pumpAndSettle();
    expect(find.text('Car Service'), findsOneWidget);

    await unmountApp(tester);
  });

  testWidgets('completing a recurring task shows the next due date',
      (tester) async {
    final due = DateTime.now().add(const Duration(hours: 1));
    // Direct db awaits must run outside the test's fake-async zone.
    await tester.runAsync(() => db.insertTask(TasksCompanion.insert(
          title: 'Water plants',
          dueAt: Value(due),
          recurrenceType: const Value(RecurrenceType.afterCompletion),
          intervalCount: const Value(3),
          intervalUnit: const Value(IntervalUnit.day),
        )));

    await pumpApp(tester);
    await tester.tap(find.text('Today'));
    await tester.pumpAndSettle();
    expect(find.text('Water plants'), findsOneWidget);

    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();
    expect(find.textContaining('Done — next:'), findsOneWidget);

    // Still recurring, so it's not gone from the database.
    final tasks =
        await tester.runAsync(() => db.watchUpcoming(DateTime.now()).first);
    expect(tasks!.single.title, 'Water plants');

    await unmountApp(tester);
  });
}
