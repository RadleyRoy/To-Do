import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import '../recurrence/recurrence_engine.dart';

part 'database.g.dart';

class TaskLists extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withLength(min: 1, max: 100)();
  IntColumn get position => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

class Tasks extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// Null for standalone timed tasks that don't live in a list.
  IntColumn get listId => integer()
      .nullable()
      .references(TaskLists, #id, onDelete: KeyAction.cascade)();
  TextColumn get title => text().withLength(min: 1, max: 300)();
  TextColumn get notes => text().nullable()();

  /// Null for plain checklist items. Recurring tasks always have a due date.
  DateTimeColumn get dueAt => dateTime().nullable()();
  BoolColumn get hasAlarm => boolean().withDefault(const Constant(false))();

  /// Ring the alarm this many minutes before [dueAt]; null/0 = at due time.
  IntColumn get reminderOffsetMinutes => integer().nullable()();

  /// When snoozed from a notification, the next reminder fires at this time
  /// instead. Cleared on complete/save.
  DateTimeColumn get snoozedUntil => dateTime().nullable()();
  IntColumn get recurrenceType =>
      intEnum<RecurrenceType>().withDefault(const Constant(0))();
  IntColumn get intervalCount => integer().nullable()();
  IntColumn get intervalUnit => intEnum<IntervalUnit>().nullable()();

  /// First occurrence of a fixed-schedule task; the schedule is computed from
  /// here so late completions never shift it.
  DateTimeColumn get anchorDate => dateTime().nullable()();

  /// Only meaningful for non-recurring tasks; recurring tasks roll over to
  /// the next due date instead of completing.
  BoolColumn get isDone => boolean().withDefault(const Constant(false))();
  IntColumn get position => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

class Subtasks extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get taskId =>
      integer().references(Tasks, #id, onDelete: KeyAction.cascade)();
  TextColumn get title => text().withLength(min: 1, max: 300)();
  BoolColumn get isDone => boolean().withDefault(const Constant(false))();
  IntColumn get position => integer().withDefault(const Constant(0))();
}

/// Completion history for recurring tasks; the latest row doubles as the
/// undo target.
class Completions extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get taskId =>
      integer().references(Tasks, #id, onDelete: KeyAction.cascade)();
  DateTimeColumn get completedAt => dateTime()();

  /// What the task's dueAt was when it got completed.
  DateTimeColumn get dueAtSnapshot => dateTime().nullable()();
}

/// UIDs of calendar events already imported, so re-importing an .ics file
/// doesn't duplicate tasks.
class ImportedEvents extends Table {
  TextColumn get icsUid => text()();
  IntColumn get taskId =>
      integer().references(Tasks, #id, onDelete: KeyAction.cascade)();

  @override
  Set<Column> get primaryKey => {icsUid};
}

class ListWithStats {
  const ListWithStats(this.list, this.totalTasks, this.doneTasks);

  final TaskList list;
  final int totalTasks;
  final int doneTasks;
}

@DriftDatabase(tables: [TaskLists, Tasks, Subtasks, Completions, ImportedEvents])
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  AppDatabase.open() : super(driftDatabase(name: 'taskley'));

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            await m.addColumn(tasks, tasks.reminderOffsetMinutes);
            await m.addColumn(tasks, tasks.snoozedUntil);
          }
        },
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON');
          // The notification background isolate opens its own connection;
          // wait instead of failing if a write briefly overlaps.
          await customStatement('PRAGMA busy_timeout = 3000');
        },
      );

  // ---------------------------------------------------------------------
  // Lists
  // ---------------------------------------------------------------------

  Stream<List<ListWithStats>> watchListsWithStats() {
    final total = taskLists.id.count(filter: tasks.id.isNotNull());
    final done = taskLists.id.count(filter: tasks.isDone.equals(true));
    final query = select(taskLists).join([
      leftOuterJoin(tasks, tasks.listId.equalsExp(taskLists.id),
          useColumns: false),
    ])
      ..addColumns([total, done])
      ..groupBy([taskLists.id])
      ..orderBy([OrderingTerm.asc(taskLists.position), OrderingTerm.asc(taskLists.id)]);
    return query.watch().map((rows) => rows
        .map((row) => ListWithStats(
            row.readTable(taskLists), row.read(total)!, row.read(done)!))
        .toList());
  }

  Future<int> createList(String name) async {
    final maxPos = await _maxListPosition();
    return into(taskLists)
        .insert(TaskListsCompanion.insert(name: name, position: Value(maxPos + 1)));
  }

  Future<int> _maxListPosition() async {
    final max = taskLists.position.max();
    final row = await (selectOnly(taskLists)..addColumns([max])).getSingle();
    return row.read(max) ?? 0;
  }

  Future<void> renameList(int id, String name) =>
      (update(taskLists)..where((l) => l.id.equals(id)))
          .write(TaskListsCompanion(name: Value(name)));

  /// Persists a drag-and-drop ordering: position = index in [orderedIds].
  Future<void> reorderLists(List<int> orderedIds) => batch((b) {
        for (final (index, id) in orderedIds.indexed) {
          b.update(taskLists, TaskListsCompanion(position: Value(index)),
              where: (TaskLists t) => t.id.equals(id));
        }
      });

  Future<void> deleteList(int id) =>
      (delete(taskLists)..where((l) => l.id.equals(id))).go();

  Future<TaskList?> getList(int id) =>
      (select(taskLists)..where((l) => l.id.equals(id))).getSingleOrNull();

  // ---------------------------------------------------------------------
  // Tasks
  // ---------------------------------------------------------------------

  Stream<List<Task>> watchTasksInList(int listId) => (select(tasks)
        ..where((t) => t.listId.equals(listId))
        ..orderBy([
          (t) => OrderingTerm.asc(t.isDone),
          (t) => OrderingTerm.asc(t.position),
          (t) => OrderingTerm.asc(t.id),
        ]))
      .watch();

  /// Overdue and today's tasks that still need doing.
  Stream<List<Task>> watchTodayAndOverdue(DateTime now) {
    final endOfDay = DateTime(now.year, now.month, now.day + 1);
    return (select(tasks)
          ..where((t) =>
              t.dueAt.isNotNull() &
              t.dueAt.isSmallerThanValue(endOfDay) &
              t.isDone.equals(false))
          ..orderBy([(t) => OrderingTerm.asc(t.dueAt)]))
        .watch();
  }

  /// Pending tasks due after today.
  Stream<List<Task>> watchUpcoming(DateTime now) {
    final endOfDay = DateTime(now.year, now.month, now.day + 1);
    return (select(tasks)
          ..where((t) =>
              t.dueAt.isBiggerOrEqualValue(endOfDay) & t.isDone.equals(false))
          ..orderBy([(t) => OrderingTerm.asc(t.dueAt)]))
        .watch();
  }

  /// All tasks due inside [start, end) — feeds the calendar view.
  Stream<List<Task>> watchTasksBetween(DateTime start, DateTime end) =>
      (select(tasks)
            ..where((t) =>
                t.dueAt.isNotNull() &
                t.dueAt.isBiggerOrEqualValue(start) &
                t.dueAt.isSmallerThanValue(end))
            ..orderBy([(t) => OrderingTerm.asc(t.dueAt)]))
          .watch();

  /// Pending tasks with an alarm — used to (re)schedule notifications.
  Future<List<Task>> tasksNeedingAlarms() => (select(tasks)
        ..where((t) =>
            t.hasAlarm.equals(true) &
            t.dueAt.isNotNull() &
            t.isDone.equals(false)))
      .get();

  Future<Task?> getTask(int id) =>
      (select(tasks)..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<int> insertTask(TasksCompanion companion) => into(tasks).insert(companion);

  Future<void> updateTask(int id, TasksCompanion companion) =>
      (update(tasks)..where((t) => t.id.equals(id))).write(companion);

  Future<void> deleteTask(int id) =>
      (delete(tasks)..where((t) => t.id.equals(id))).go();

  /// Persists a drag-and-drop ordering of tasks within a list.
  Future<void> reorderTasks(List<int> orderedIds) => batch((b) {
        for (final (index, id) in orderedIds.indexed) {
          b.update(tasks, TasksCompanion(position: Value(index)),
              where: (Tasks t) => t.id.equals(id));
        }
      });

  /// Snoozes the task's reminder until [until]; returns the updated task.
  Future<Task> snoozeTask(int id, DateTime until) async {
    await updateTask(id, TasksCompanion(snoozedUntil: Value(until)));
    return (await getTask(id))!;
  }

  // ---------------------------------------------------------------------
  // Completing tasks
  // ---------------------------------------------------------------------

  /// Completes [task]. Non-recurring tasks are marked done; recurring tasks
  /// log a completion and roll `dueAt` forward per their recurrence rule.
  /// Returns the updated task.
  Future<Task> completeTask(Task task, {DateTime? now}) async {
    final at = now ?? DateTime.now();
    return transaction(() async {
      if (task.recurrenceType == RecurrenceType.none) {
        await updateTask(task.id,
            const TasksCompanion(isDone: Value(true), snoozedUntil: Value(null)));
        return (await getTask(task.id))!;
      }
      final interval =
          RecurrenceInterval(task.intervalCount!, task.intervalUnit!);
      await into(completions).insert(CompletionsCompanion.insert(
        taskId: task.id,
        completedAt: at,
        dueAtSnapshot: Value(task.dueAt),
      ));
      final nextDue = switch (task.recurrenceType) {
        RecurrenceType.afterCompletion => nextAfterCompletion(
            completedAt: at,
            previousDue: task.dueAt ?? at,
            interval: interval,
          ),
        RecurrenceType.fixedSchedule => nextFixed(
            anchor: task.anchorDate ?? task.dueAt ?? at,
            interval: interval,
            after: at,
          ),
        RecurrenceType.none => throw StateError('unreachable'),
      };
      await updateTask(task.id,
          TasksCompanion(dueAt: Value(nextDue), snoozedUntil: const Value(null)));
      return (await getTask(task.id))!;
    });
  }

  /// Undoes the most recent completion. For recurring tasks this pops the
  /// latest history row and restores the due date it snapshotted. Returns the
  /// updated task.
  Future<Task> uncompleteTask(Task task) async {
    return transaction(() async {
      if (task.recurrenceType == RecurrenceType.none) {
        await updateTask(task.id, const TasksCompanion(isDone: Value(false)));
        return (await getTask(task.id))!;
      }
      final latest = await (select(completions)
            ..where((c) => c.taskId.equals(task.id))
            ..orderBy([(c) => OrderingTerm.desc(c.id)])
            ..limit(1))
          .getSingleOrNull();
      if (latest != null) {
        await (delete(completions)..where((c) => c.id.equals(latest.id))).go();
        await updateTask(
            task.id,
            TasksCompanion(
                dueAt: Value(latest.dueAtSnapshot),
                snoozedUntil: const Value(null)));
      }
      return (await getTask(task.id))!;
    });
  }

  Stream<List<Completion>> watchCompletions(int taskId) => (select(completions)
        ..where((c) => c.taskId.equals(taskId))
        ..orderBy([(c) => OrderingTerm.desc(c.completedAt)]))
      .watch();

  // ---------------------------------------------------------------------
  // Subtasks
  // ---------------------------------------------------------------------

  Stream<List<Subtask>> watchSubtasks(int taskId) => (select(subtasks)
        ..where((s) => s.taskId.equals(taskId))
        ..orderBy([(s) => OrderingTerm.asc(s.position), (s) => OrderingTerm.asc(s.id)]))
      .watch();

  Future<List<Subtask>> getSubtasks(int taskId) =>
      (select(subtasks)..where((s) => s.taskId.equals(taskId))).get();

  Future<int> addSubtask(int taskId, String title) async {
    final max = subtasks.position.max();
    final row = await (selectOnly(subtasks)
          ..addColumns([max])
          ..where(subtasks.taskId.equals(taskId)))
        .getSingle();
    final position = (row.read(max) ?? 0) + 1;
    return into(subtasks).insert(SubtasksCompanion.insert(
        taskId: taskId, title: title, position: Value(position)));
  }

  Future<void> updateSubtaskTitle(int id, String title) =>
      (update(subtasks)..where((s) => s.id.equals(id)))
          .write(SubtasksCompanion(title: Value(title)));

  Future<void> setSubtaskDone(int id, bool isDone) =>
      (update(subtasks)..where((s) => s.id.equals(id)))
          .write(SubtasksCompanion(isDone: Value(isDone)));

  Future<void> deleteSubtask(int id) =>
      (delete(subtasks)..where((s) => s.id.equals(id))).go();

  // ---------------------------------------------------------------------
  // ICS import bookkeeping
  // ---------------------------------------------------------------------

  Future<Set<String>> importedEventUids() async {
    final rows = await select(importedEvents).get();
    return rows.map((r) => r.icsUid).toSet();
  }

  Future<void> recordImportedEvent(String uid, int taskId) =>
      into(importedEvents).insert(
          ImportedEventsCompanion.insert(icsUid: uid, taskId: taskId),
          mode: InsertMode.insertOrReplace);

  // ---------------------------------------------------------------------
  // Backup / restore
  // ---------------------------------------------------------------------

  static const backupSchemaVersion = 2;

  Future<Map<String, dynamic>> exportData() async {
    final lists = await select(taskLists).get();
    final allTasks = await select(tasks).get();
    final allSubtasks = await select(subtasks).get();
    final allCompletions = await select(completions).get();
    final imported = await select(importedEvents).get();
    return {
      'schemaVersion': backupSchemaVersion,
      'exportedAt': DateTime.now().toIso8601String(),
      'lists': lists.map((e) => e.toJson()).toList(),
      'tasks': allTasks.map((e) => e.toJson()).toList(),
      'subtasks': allSubtasks.map((e) => e.toJson()).toList(),
      'completions': allCompletions.map((e) => e.toJson()).toList(),
      'importedEvents': imported.map((e) => e.toJson()).toList(),
    };
  }

  /// Replaces all data with the backup's contents. Throws [FormatException]
  /// on unusable input; runs in a transaction so failures leave data intact.
  Future<void> importData(Map<String, dynamic> data) async {
    final version = data['schemaVersion'];
    if (version is! int || version > backupSchemaVersion) {
      throw FormatException(
          'Unsupported backup version: ${data['schemaVersion']}');
    }
    List<T> parseAll<T>(String key, T Function(Map<String, dynamic>) fromJson) {
      final raw = data[key];
      if (raw == null) return const [];
      if (raw is! List) throw FormatException('"$key" is not a list');
      return raw
          .map((e) => fromJson((e as Map).cast<String, dynamic>()))
          .toList();
    }

    final lists = parseAll('lists', TaskList.fromJson);
    final allTasks = parseAll('tasks', Task.fromJson);
    final allSubtasks = parseAll('subtasks', Subtask.fromJson);
    final allCompletions = parseAll('completions', Completion.fromJson);
    final imported = parseAll('importedEvents', ImportedEvent.fromJson);

    await transaction(() async {
      await delete(importedEvents).go();
      await delete(completions).go();
      await delete(subtasks).go();
      await delete(tasks).go();
      await delete(taskLists).go();
      await batch((b) {
        b.insertAll(taskLists, lists.map((e) => e.toCompanion(false)));
        b.insertAll(tasks, allTasks.map((e) => e.toCompanion(false)));
        b.insertAll(subtasks, allSubtasks.map((e) => e.toCompanion(false)));
        b.insertAll(
            completions, allCompletions.map((e) => e.toCompanion(false)));
        b.insertAll(importedEvents, imported.map((e) => e.toCompanion(false)));
      });
    });
  }
}
