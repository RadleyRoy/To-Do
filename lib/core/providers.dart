import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'db/database.dart';
import 'notifications/notification_service.dart';
import 'utils/date_utils.dart';
import 'widget/home_widget_service.dart';

/// Overridden with real instances in main().
final databaseProvider = Provider<AppDatabase>((ref) => throw UnimplementedError());
final notificationServiceProvider =
    Provider<NotificationService>((ref) => throw UnimplementedError());
final homeWidgetServiceProvider =
    Provider<HomeWidgetService>((ref) => HomeWidgetService());

final listsWithStatsProvider = StreamProvider<List<ListWithStats>>(
    (ref) => ref.watch(databaseProvider).watchListsWithStats());

final tasksInListProvider = StreamProvider.family<List<Task>, int>(
    (ref, listId) => ref.watch(databaseProvider).watchTasksInList(listId));

final listProvider = FutureProvider.family<TaskList?, int>(
    (ref, id) => ref.watch(databaseProvider).getList(id));

final todayTasksProvider = StreamProvider<List<Task>>(
    (ref) => ref.watch(databaseProvider).watchTodayAndOverdue(DateTime.now()));

final upcomingTasksProvider = StreamProvider<List<Task>>(
    (ref) => ref.watch(databaseProvider).watchUpcoming(DateTime.now()));

final subtasksProvider = StreamProvider.family<List<Subtask>, int>(
    (ref, taskId) => ref.watch(databaseProvider).watchSubtasks(taskId));

/// Tasks grouped by day for the calendar's visible range around a month.
final calendarTasksProvider =
    StreamProvider.family<Map<DateTime, List<Task>>, DateTime>((ref, month) {
  // TableCalendar shows up to ~2 weeks of neighbouring months in the grid.
  final start = DateTime(month.year, month.month - 1, 15);
  final end = DateTime(month.year, month.month + 2, 15);
  return ref.watch(databaseProvider).watchTasksBetween(start, end).map((tasks) {
    final byDay = <DateTime, List<Task>>{};
    for (final task in tasks) {
      byDay.putIfAbsent(dateOnly(task.dueAt!), () => []).add(task);
    }
    return byDay;
  });
});
