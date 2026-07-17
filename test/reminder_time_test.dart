import 'package:flutter_test/flutter_test.dart';
import 'package:taskley/core/db/database.dart';
import 'package:taskley/core/notifications/notification_service.dart';
import 'package:taskley/core/recurrence/recurrence_engine.dart';

Task _task({
  DateTime? dueAt,
  bool hasAlarm = true,
  bool isDone = false,
  int? offsetMinutes,
  DateTime? snoozedUntil,
}) =>
    Task(
      id: 1,
      title: 'T',
      dueAt: dueAt,
      hasAlarm: hasAlarm,
      isDone: isDone,
      reminderOffsetMinutes: offsetMinutes,
      snoozedUntil: snoozedUntil,
      recurrenceType: RecurrenceType.none,
      position: 0,
      createdAt: DateTime(2026),
    );

void main() {
  final now = DateTime(2026, 7, 17, 12, 0);
  final due = DateTime(2026, 7, 20, 10, 0);

  test('rings at the due time by default', () {
    expect(NotificationService.reminderTime(_task(dueAt: due), now: now), due);
  });

  test('reminder offset moves the alarm earlier', () {
    expect(
        NotificationService.reminderTime(
            _task(dueAt: due, offsetMinutes: 1440),
            now: now),
        DateTime(2026, 7, 19, 10, 0));
  });

  test('snooze overrides due-based time', () {
    final snoozed = DateTime(2026, 7, 17, 13, 0);
    expect(
        NotificationService.reminderTime(
            _task(dueAt: due, snoozedUntil: snoozed),
            now: now),
        snoozed);
  });

  test('expired snooze falls back to due-based time', () {
    expect(
        NotificationService.reminderTime(
            _task(dueAt: due, snoozedUntil: DateTime(2026, 7, 17, 11, 0)),
            now: now),
        due);
  });

  test('no reminder when done, alarm off, or time has passed', () {
    expect(NotificationService.reminderTime(_task(dueAt: due, isDone: true), now: now),
        isNull);
    expect(
        NotificationService.reminderTime(_task(dueAt: due, hasAlarm: false), now: now),
        isNull);
    expect(
        NotificationService.reminderTime(
            _task(dueAt: DateTime(2026, 7, 17, 11, 0)),
            now: now),
        isNull);
    expect(NotificationService.reminderTime(_task(dueAt: null), now: now), isNull);
  });
}
