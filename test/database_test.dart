import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskley/core/db/database.dart';
import 'package:taskley/core/recurrence/recurrence_engine.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  group('lists and checklist items', () {
    test('create list, add items, toggle done and back', () async {
      final listId = await db.createList('Groceries');
      final taskId = await db.insertTask(TasksCompanion.insert(
          title: 'Milk', listId: Value(listId)));

      var task = (await db.getTask(taskId))!;
      expect(task.isDone, isFalse);

      task = await db.completeTask(task);
      expect(task.isDone, isTrue);

      task = await db.uncompleteTask(task);
      expect(task.isDone, isFalse);
    });

    test('list stats count tasks and done tasks', () async {
      final listId = await db.createList('Groceries');
      await db.insertTask(
          TasksCompanion.insert(title: 'Milk', listId: Value(listId)));
      final eggsId = await db.insertTask(
          TasksCompanion.insert(title: 'Eggs', listId: Value(listId)));
      await db.completeTask((await db.getTask(eggsId))!);

      final stats = await db.watchListsWithStats().first;
      expect(stats, hasLength(1));
      expect(stats.first.totalTasks, 2);
      expect(stats.first.doneTasks, 1);
    });

    test('deleting a list cascades to its tasks and subtasks', () async {
      final listId = await db.createList('Groceries');
      final taskId = await db.insertTask(
          TasksCompanion.insert(title: 'Milk', listId: Value(listId)));
      await db.addSubtask(taskId, 'Semi-skimmed');

      await db.deleteList(listId);
      expect(await db.getTask(taskId), isNull);
      expect(await db.getSubtasks(taskId), isEmpty);
    });
  });

  group('recurring tasks', () {
    test('afterCompletion rolls due date forward from completion', () async {
      final taskId = await db.insertTask(TasksCompanion.insert(
        title: 'Car Service',
        dueAt: Value(DateTime(2026, 3, 1, 9, 0)),
        recurrenceType: const Value(RecurrenceType.afterCompletion),
        intervalCount: const Value(6),
        intervalUnit: const Value(IntervalUnit.month),
      ));

      final completedOn = DateTime(2026, 5, 20, 11, 30);
      final task =
          await db.completeTask((await db.getTask(taskId))!, now: completedOn);

      expect(task.isDone, isFalse);
      expect(task.dueAt, DateTime(2026, 11, 20, 9, 0));

      final history = await db.watchCompletions(taskId).first;
      expect(history, hasLength(1));
      expect(history.first.dueAtSnapshot, DateTime(2026, 3, 1, 9, 0));
    });

    test('completing a fixed task before its due time still advances it',
        () async {
      // Regression: task due today 21:00, every 2 months fixed, completed at
      // 14:00 the same day — the next occurrence must be 2 months out, not
      // today 21:00 again.
      final taskId = await db.insertTask(TasksCompanion.insert(
        title: 'Deep clean',
        dueAt: Value(DateTime(2026, 7, 17, 21, 0)),
        anchorDate: Value(DateTime(2026, 7, 17, 21, 0)),
        recurrenceType: const Value(RecurrenceType.fixedSchedule),
        intervalCount: const Value(2),
        intervalUnit: const Value(IntervalUnit.month),
      ));

      final task = await db.completeTask((await db.getTask(taskId))!,
          now: DateTime(2026, 7, 17, 14, 0));
      expect(task.dueAt, DateTime(2026, 9, 17, 21, 0));
    });

    test('fixedSchedule keeps the calendar anchor', () async {
      final taskId = await db.insertTask(TasksCompanion.insert(
        title: "Mom's birthday",
        dueAt: Value(DateTime(2026, 3, 10, 9, 0)),
        anchorDate: Value(DateTime(2026, 3, 10, 9, 0)),
        recurrenceType: const Value(RecurrenceType.fixedSchedule),
        intervalCount: const Value(1),
        intervalUnit: const Value(IntervalUnit.year),
      ));

      final task = await db.completeTask((await db.getTask(taskId))!,
          now: DateTime(2026, 4, 2, 14, 0));
      expect(task.dueAt, DateTime(2027, 3, 10, 9, 0));
    });

    test('uncomplete restores the previous due date', () async {
      final taskId = await db.insertTask(TasksCompanion.insert(
        title: 'Water plants',
        dueAt: Value(DateTime(2026, 7, 1, 8, 0)),
        recurrenceType: const Value(RecurrenceType.afterCompletion),
        intervalCount: const Value(3),
        intervalUnit: const Value(IntervalUnit.day),
      ));

      var task = (await db.getTask(taskId))!;
      task = await db.completeTask(task, now: DateTime(2026, 7, 2, 20, 0));
      expect(task.dueAt, DateTime(2026, 7, 5, 8, 0));

      task = await db.uncompleteTask(task);
      expect(task.dueAt, DateTime(2026, 7, 1, 8, 0));
      expect(await db.watchCompletions(taskId).first, isEmpty);
    });
  });

  group('snooze', () {
    test('snoozeTask sets snoozedUntil and completing clears it', () async {
      final taskId = await db.insertTask(TasksCompanion.insert(
        title: 'Water plants',
        dueAt: Value(DateTime(2026, 7, 1, 8, 0)),
        hasAlarm: const Value(true),
        recurrenceType: const Value(RecurrenceType.afterCompletion),
        intervalCount: const Value(3),
        intervalUnit: const Value(IntervalUnit.day),
      ));

      final until = DateTime(2026, 7, 1, 9, 0);
      var task = await db.snoozeTask(taskId, until);
      expect(task.snoozedUntil, until);

      task = await db.completeTask(task, now: DateTime(2026, 7, 1, 10, 0));
      expect(task.snoozedUntil, isNull);
      expect(task.dueAt, DateTime(2026, 7, 4, 8, 0));
    });
  });

  group('reordering', () {
    test('reorderTasks persists drag order within a list', () async {
      final listId = await db.createList('Groceries');
      final a = await db.insertTask(
          TasksCompanion.insert(title: 'A', listId: Value(listId)));
      final b = await db.insertTask(
          TasksCompanion.insert(title: 'B', listId: Value(listId)));
      final c = await db.insertTask(
          TasksCompanion.insert(title: 'C', listId: Value(listId)));

      await db.reorderTasks([c, a, b]);
      final tasks = await db.watchTasksInList(listId).first;
      expect(tasks.map((t) => t.title), ['C', 'A', 'B']);
    });

    test('reorderLists persists drag order', () async {
      final one = await db.createList('One');
      final two = await db.createList('Two');
      await db.reorderLists([two, one]);
      final lists = await db.watchListsWithStats().first;
      expect(lists.map((l) => l.list.name), ['Two', 'One']);
    });
  });

  group('smart views', () {
    test('today includes overdue, upcoming excludes done', () async {
      final now = DateTime(2026, 7, 17, 12, 0);
      await db.insertTask(TasksCompanion.insert(
          title: 'Overdue', dueAt: Value(DateTime(2026, 7, 10, 9, 0))));
      await db.insertTask(TasksCompanion.insert(
          title: 'Today', dueAt: Value(DateTime(2026, 7, 17, 18, 0))));
      await db.insertTask(TasksCompanion.insert(
          title: 'Tomorrow', dueAt: Value(DateTime(2026, 7, 18, 9, 0))));
      final doneId = await db.insertTask(TasksCompanion.insert(
          title: 'Done future', dueAt: Value(DateTime(2026, 7, 20, 9, 0))));
      await db.completeTask((await db.getTask(doneId))!);

      final today = await db.watchTodayAndOverdue(now).first;
      expect(today.map((t) => t.title), ['Overdue', 'Today']);

      final upcoming = await db.watchUpcoming(now).first;
      expect(upcoming.map((t) => t.title), ['Tomorrow']);
    });
  });

  group('backup round-trip', () {
    test('export then import restores identical data', () async {
      final listId = await db.createList('Groceries');
      final taskId = await db.insertTask(TasksCompanion.insert(
        title: 'Car Service',
        listId: Value(listId),
        notes: const Value('Use the good garage'),
        dueAt: Value(DateTime(2026, 9, 1, 10, 0)),
        hasAlarm: const Value(true),
        recurrenceType: const Value(RecurrenceType.afterCompletion),
        intervalCount: const Value(6),
        intervalUnit: const Value(IntervalUnit.month),
      ));
      await db.addSubtask(taskId, 'Book appointment');
      await db.completeTask((await db.getTask(taskId))!,
          now: DateTime(2026, 9, 2, 15, 0));
      await db.recordImportedEvent('uid-1@google.com', taskId);

      final exported = await db.exportData();

      final restored = AppDatabase(NativeDatabase.memory());
      addTearDown(restored.close);
      await restored.importData(exported);

      final reExported = await restored.exportData();
      for (final key in ['lists', 'tasks', 'subtasks', 'completions', 'importedEvents']) {
        expect(reExported[key], exported[key], reason: key);
      }
    });

    test('import rejects unknown versions', () async {
      expect(db.importData({'schemaVersion': 999}), throwsFormatException);
      expect(db.importData({}), throwsFormatException);
    });
  });
}
