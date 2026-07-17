import 'package:flutter_test/flutter_test.dart';
import 'package:taskley/core/recurrence/recurrence_engine.dart';

void main() {
  group('addIntervalTimes', () {
    test('adds days and weeks', () {
      final from = DateTime(2026, 1, 30, 9, 0);
      expect(addIntervalTimes(from, const RecurrenceInterval(3, IntervalUnit.day), 1),
          DateTime(2026, 2, 2, 9, 0));
      expect(addIntervalTimes(from, const RecurrenceInterval(2, IntervalUnit.week), 1),
          DateTime(2026, 2, 13, 9, 0));
    });

    test('clamps month-end: Aug 31 + 6 months -> Feb 28 on non-leap years', () {
      expect(
          addIntervalTimes(DateTime(2026, 8, 31, 10, 0),
              const RecurrenceInterval(6, IntervalUnit.month), 1),
          DateTime(2027, 2, 28, 10, 0));
    });

    test('keeps Feb 29 when landing on a leap year', () {
      expect(
          addIntervalTimes(DateTime(2027, 8, 31, 10, 0),
              const RecurrenceInterval(6, IntervalUnit.month), 1),
          DateTime(2028, 2, 29, 10, 0));
    });

    test('multiplies interval by times from the anchor', () {
      final anchor = DateTime(2026, 1, 31, 8, 0);
      expect(addIntervalTimes(anchor, const RecurrenceInterval(1, IntervalUnit.month), 2),
          DateTime(2026, 3, 31, 8, 0));
    });
  });

  group('nextAfterCompletion', () {
    test('schedules from completion date, keeping the due time-of-day', () {
      final next = nextAfterCompletion(
        completedAt: DateTime(2026, 1, 15, 16, 42),
        previousDue: DateTime(2026, 1, 10, 10, 0),
        interval: const RecurrenceInterval(6, IntervalUnit.month),
      );
      expect(next, DateTime(2026, 7, 15, 10, 0));
    });

    test('late car service pushes the next one out', () {
      // Due in March, done two months late in May -> next is November.
      final next = nextAfterCompletion(
        completedAt: DateTime(2026, 5, 20, 11, 30),
        previousDue: DateTime(2026, 3, 1, 9, 0),
        interval: const RecurrenceInterval(6, IntervalUnit.month),
      );
      expect(next, DateTime(2026, 11, 20, 9, 0));
    });
  });

  group('nextFixed', () {
    const yearly = RecurrenceInterval(1, IntervalUnit.year);

    test('future anchor is returned as-is', () {
      final anchor = DateTime(2026, 12, 25, 9, 0);
      expect(
          nextFixed(anchor: anchor, interval: yearly, after: DateTime(2026, 7, 1)),
          anchor);
    });

    test('completing late does not shift the schedule', () {
      // Birthday on Mar 10; marked done on Apr 2 -> next is Mar 10 next year.
      final next = nextFixed(
        anchor: DateTime(2020, 3, 10, 9, 0),
        interval: yearly,
        after: DateTime(2026, 4, 2, 14, 0),
      );
      expect(next, DateTime(2027, 3, 10, 9, 0));
    });

    test('monthly schedule anchored on Jan 31 does not drift after February', () {
      final next = nextFixed(
        anchor: DateTime(2026, 1, 31, 9, 0),
        interval: const RecurrenceInterval(1, IntervalUnit.month),
        after: DateTime(2026, 2, 28, 12, 0),
      );
      expect(next, DateTime(2026, 3, 31, 9, 0));
    });

    test('Feb 29 anchor falls back to Feb 28 and recovers on leap years', () {
      final anchor = DateTime(2024, 2, 29, 9, 0);
      expect(nextFixed(anchor: anchor, interval: yearly, after: DateTime(2024, 3, 1)),
          DateTime(2025, 2, 28, 9, 0));
      expect(nextFixed(anchor: anchor, interval: yearly, after: DateTime(2027, 3, 1)),
          DateTime(2028, 2, 29, 9, 0));
    });

    test('occurrence exactly at "after" moves to the next one', () {
      final anchor = DateTime(2026, 1, 1, 9, 0);
      expect(
          nextFixed(
              anchor: anchor,
              interval: const RecurrenceInterval(1, IntervalUnit.week),
              after: DateTime(2026, 1, 8, 9, 0)),
          DateTime(2026, 1, 15, 9, 0));
    });
  });

  test('daysInMonth handles leap years', () {
    expect(daysInMonth(2024, 2), 29);
    expect(daysInMonth(2025, 2), 28);
    expect(daysInMonth(2026, 4), 30);
    expect(daysInMonth(2026, 12), 31);
  });
}
