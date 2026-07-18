import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/database.dart';
import '../../core/notifications/notification_service.dart';
import '../../core/providers.dart';
import '../../core/recurrence/recurrence_engine.dart';
import '../../core/widget/home_widget_service.dart';

final taskActionsProvider = Provider<TaskActions>((ref) => TaskActions(
    ref.watch(databaseProvider),
    ref.watch(notificationServiceProvider),
    ref.watch(homeWidgetServiceProvider)));

/// One draft row in the task editor's subtask list; id is null until saved.
class SubtaskDraft {
  SubtaskDraft({this.id, required this.title, this.isDone = false});

  final int? id;
  String title;
  bool isDone;
}

/// Mutations that must keep the database, scheduled alarms, and the
/// home-screen widget in sync.
class TaskActions {
  TaskActions(this._db, this._notifications, this._homeWidget);

  final AppDatabase _db;
  final NotificationService _notifications;
  final HomeWidgetService _homeWidget;

  Future<void> _refreshWidget() => _homeWidget.refresh(_db);

  /// Completes [task]; pass [on] to record it as done on another day
  /// (after-completion recurrence then counts from that day).
  Future<Task> complete(Task task, {DateTime? on}) async {
    final updated = await _db.completeTask(task, now: on);
    await _notifications.syncTaskReminder(updated);
    await _refreshWidget();
    return updated;
  }

  Future<Task> uncomplete(Task task) async {
    final updated = await _db.uncompleteTask(task);
    await _notifications.syncTaskReminder(updated);
    await _refreshWidget();
    return updated;
  }

  /// Snoozes the task's reminder to now + [duration].
  Future<Task> snooze(Task task, Duration duration) async {
    final updated =
        await _db.snoozeTask(task.id, DateTime.now().add(duration));
    await _notifications.syncTaskReminder(updated);
    return updated;
  }

  /// Deletes [task] and returns an undo closure that restores it (with its
  /// subtasks) exactly as it was.
  Future<Future<void> Function()> delete(Task task) async {
    final subtasks = await _db.getSubtasks(task.id);
    await _db.deleteTask(task.id);
    await _notifications.cancelTaskReminder(task.id);
    await _refreshWidget();
    return () async {
      await _db.restoreTask(task, subtasks);
      await _notifications.syncTaskReminder(task);
      await _refreshWidget();
    };
  }

  Future<int> addChecklistItem(int listId, String title) async {
    final id = await _db
        .insertTask(TasksCompanion.insert(title: title, listId: Value(listId)));
    await _refreshWidget();
    return id;
  }

  /// Inserts or updates a task from the editor and reconciles its subtasks
  /// and alarm. Returns the task id.
  Future<int> saveTask({
    int? id,
    required String title,
    String? notes,
    int? listId,
    DateTime? dueAt,
    required bool hasAlarm,
    int? reminderOffsetMinutes,
    required RecurrenceType recurrenceType,
    RecurrenceInterval? interval,
    List<SubtaskDraft> subtasks = const [],
  }) async {
    final recurring = recurrenceType != RecurrenceType.none;
    final alarm = hasAlarm && dueAt != null;
    final companion = TasksCompanion(
      title: Value(title),
      notes: Value(notes),
      listId: Value(listId),
      dueAt: Value(dueAt),
      hasAlarm: Value(alarm),
      reminderOffsetMinutes: Value(alarm ? reminderOffsetMinutes : null),
      recurrenceType: Value(recurrenceType),
      intervalCount: Value(recurring ? interval?.count : null),
      intervalUnit: Value(recurring ? interval?.unit : null),
      // Fixed schedules are (re-)anchored at whatever due date was saved.
      anchorDate:
          Value(recurrenceType == RecurrenceType.fixedSchedule ? dueAt : null),
      // Editing a done task's date/recurrence brings it back, and any old
      // snooze no longer applies.
      isDone: const Value(false),
      snoozedUntil: const Value(null),
    );

    final int taskId;
    if (id == null) {
      taskId = await _db.insertTask(companion);
    } else {
      taskId = id;
      await _db.updateTask(id, companion);
    }

    await _syncSubtasks(taskId, subtasks);

    final saved = await _db.getTask(taskId);
    if (saved != null) await _notifications.syncTaskReminder(saved);
    await _refreshWidget();
    return taskId;
  }

  Future<void> _syncSubtasks(int taskId, List<SubtaskDraft> drafts) async {
    final existing = await _db.getSubtasks(taskId);
    final keptIds = drafts.map((d) => d.id).whereType<int>().toSet();
    for (final sub in existing) {
      if (!keptIds.contains(sub.id)) await _db.deleteSubtask(sub.id);
    }
    for (final draft in drafts) {
      final title = draft.title.trim();
      if (title.isEmpty) continue;
      if (draft.id == null) {
        final newId = await _db.addSubtask(taskId, title);
        if (draft.isDone) await _db.setSubtaskDone(newId, true);
      } else {
        final before = existing.where((s) => s.id == draft.id).firstOrNull;
        if (before == null) continue;
        if (before.title != title) {
          await _db.updateSubtaskTitle(draft.id!, title);
        }
        if (before.isDone != draft.isDone) {
          await _db.setSubtaskDone(draft.id!, draft.isDone);
        }
      }
    }
  }
}
