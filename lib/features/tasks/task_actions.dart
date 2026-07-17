import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/database.dart';
import '../../core/notifications/notification_service.dart';
import '../../core/providers.dart';
import '../../core/recurrence/recurrence_engine.dart';

final taskActionsProvider = Provider<TaskActions>((ref) => TaskActions(
    ref.watch(databaseProvider), ref.watch(notificationServiceProvider)));

/// One draft row in the task editor's subtask list; id is null until saved.
class SubtaskDraft {
  SubtaskDraft({this.id, required this.title, this.isDone = false});

  final int? id;
  String title;
  bool isDone;
}

/// Mutations that must keep the database and scheduled alarms in sync.
class TaskActions {
  TaskActions(this._db, this._notifications);

  final AppDatabase _db;
  final NotificationService _notifications;

  Future<Task> complete(Task task) async {
    final updated = await _db.completeTask(task);
    await _notifications.syncTaskReminder(updated);
    return updated;
  }

  Future<Task> uncomplete(Task task) async {
    final updated = await _db.uncompleteTask(task);
    await _notifications.syncTaskReminder(updated);
    return updated;
  }

  Future<void> delete(Task task) async {
    await _db.deleteTask(task.id);
    await _notifications.cancelTaskReminder(task.id);
  }

  Future<int> addChecklistItem(int listId, String title) =>
      _db.insertTask(TasksCompanion.insert(title: title, listId: Value(listId)));

  /// Inserts or updates a task from the editor and reconciles its subtasks
  /// and alarm. Returns the task id.
  Future<int> saveTask({
    int? id,
    required String title,
    String? notes,
    int? listId,
    DateTime? dueAt,
    required bool hasAlarm,
    required RecurrenceType recurrenceType,
    RecurrenceInterval? interval,
    List<SubtaskDraft> subtasks = const [],
  }) async {
    final recurring = recurrenceType != RecurrenceType.none;
    final companion = TasksCompanion(
      title: Value(title),
      notes: Value(notes),
      listId: Value(listId),
      dueAt: Value(dueAt),
      hasAlarm: Value(hasAlarm && dueAt != null),
      recurrenceType: Value(recurrenceType),
      intervalCount: Value(recurring ? interval?.count : null),
      intervalUnit: Value(recurring ? interval?.unit : null),
      // Fixed schedules are (re-)anchored at whatever due date was saved.
      anchorDate:
          Value(recurrenceType == RecurrenceType.fixedSchedule ? dueAt : null),
      // Editing a done task's date/recurrence brings it back.
      isDone: const Value(false),
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
