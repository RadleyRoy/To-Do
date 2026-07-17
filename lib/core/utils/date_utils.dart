import 'package:intl/intl.dart';

DateTime dateOnly(DateTime dt) => DateTime(dt.year, dt.month, dt.day);

bool isSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// "Today 18:00", "Tomorrow 09:00", "Mon, 20 Jul" or "20 Jul 2027" for
/// dates beyond this year. Omits the time when it's exactly midnight
/// (all-day tasks).
String formatDue(DateTime due, {DateTime? now}) {
  final ref = now ?? DateTime.now();
  final time = due.hour == 0 && due.minute == 0
      ? ''
      : ' ${DateFormat.Hm().format(due)}';

  if (isSameDay(due, ref)) return 'Today$time';
  if (isSameDay(due, ref.add(const Duration(days: 1)))) return 'Tomorrow$time';
  if (isSameDay(due, ref.subtract(const Duration(days: 1)))) {
    return 'Yesterday$time';
  }
  final sameYear = due.year == ref.year;
  final date = sameYear
      ? DateFormat('E, d MMM').format(due)
      : DateFormat('d MMM y').format(due);
  return '$date$time';
}

String formatDayHeader(DateTime day, {DateTime? now}) {
  final ref = now ?? DateTime.now();
  if (isSameDay(day, ref)) return 'Today';
  if (isSameDay(day, ref.add(const Duration(days: 1)))) return 'Tomorrow';
  return DateFormat('EEEE, d MMMM').format(day);
}
