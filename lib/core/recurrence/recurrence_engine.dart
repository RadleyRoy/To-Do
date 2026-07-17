/// Pure date arithmetic for recurring tasks. No Flutter imports so it can be
/// unit-tested on the Dart VM.
library;

enum RecurrenceType {
  /// Not recurring: completing the task marks it done permanently.
  none,

  /// Next occurrence = completion date + interval ("Car Service every 6
  /// months": doing it late pushes the next one out).
  afterCompletion,

  /// Occurrences follow the calendar from a fixed anchor date ("Birthday
  /// every year"): completing late never shifts the schedule.
  fixedSchedule,
}

enum IntervalUnit { day, week, month, year }

class RecurrenceInterval {
  const RecurrenceInterval(this.count, this.unit) : assert(count > 0);

  final int count;
  final IntervalUnit unit;

  String describe() {
    final unitName = switch (unit) {
      IntervalUnit.day => 'day',
      IntervalUnit.week => 'week',
      IntervalUnit.month => 'month',
      IntervalUnit.year => 'year',
    };
    return count == 1 ? 'every $unitName' : 'every $count ${unitName}s';
  }

  @override
  bool operator ==(Object other) =>
      other is RecurrenceInterval && other.count == count && other.unit == unit;

  @override
  int get hashCode => Object.hash(count, unit);
}

int daysInMonth(int year, int month) => DateTime(year, month + 1, 0).day;

/// Adds [interval] to [from] [times] times in one step, anchored on [from].
///
/// Month/year additions clamp to the last day of the target month
/// (Aug 31 + 6 months -> Feb 28/29). Computing "anchor + n * interval" in a
/// single step (instead of repeatedly adding) keeps fixed schedules from
/// drifting after a clamped occurrence (Jan 31 -> Feb 28 -> Mar 31, not
/// Mar 28). Uses calendar arithmetic, not Duration, so results keep the
/// wall-clock time across DST changes.
DateTime addIntervalTimes(DateTime from, RecurrenceInterval interval, int times) {
  final n = interval.count * times;
  return switch (interval.unit) {
    IntervalUnit.day =>
        DateTime(from.year, from.month, from.day + n, from.hour, from.minute),
    IntervalUnit.week =>
        DateTime(from.year, from.month, from.day + 7 * n, from.hour, from.minute),
    IntervalUnit.month => _addMonths(from, n),
    IntervalUnit.year => _addMonths(from, 12 * n),
  };
}

DateTime _addMonths(DateTime from, int months) {
  final zeroBased = from.year * 12 + (from.month - 1) + months;
  final year = zeroBased ~/ 12;
  final month = zeroBased % 12 + 1;
  final day =
      from.day <= daysInMonth(year, month) ? from.day : daysInMonth(year, month);
  return DateTime(year, month, day, from.hour, from.minute);
}

/// Next due date for an [RecurrenceType.afterCompletion] task.
///
/// The next occurrence lands `interval` after the day the task was actually
/// completed, keeping the scheduled time-of-day from [previousDue] (completing
/// "Car Service, due 10:00" at 16:42 schedules the next one at 10:00).
DateTime nextAfterCompletion({
  required DateTime completedAt,
  required DateTime previousDue,
  required RecurrenceInterval interval,
}) {
  final base = DateTime(completedAt.year, completedAt.month, completedAt.day,
      previousDue.hour, previousDue.minute);
  return addIntervalTimes(base, interval, 1);
}

/// Next due date for a [RecurrenceType.fixedSchedule] task: the earliest
/// `anchor + n * interval` (n >= 0) strictly after [after].
DateTime nextFixed({
  required DateTime anchor,
  required RecurrenceInterval interval,
  required DateTime after,
}) {
  if (anchor.isAfter(after)) return anchor;
  var n = 1;
  var candidate = addIntervalTimes(anchor, interval, n);
  while (!candidate.isAfter(after)) {
    n += 1;
    candidate = addIntervalTimes(anchor, interval, n);
  }
  return candidate;
}
