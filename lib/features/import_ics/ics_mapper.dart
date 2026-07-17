import 'package:icalendar_parser/icalendar_parser.dart';

/// A calendar event extracted from an .ics export, reduced to what Taskley
/// can import. Pure Dart so the mapping is unit-testable.
class IcsEvent {
  const IcsEvent({
    required this.uid,
    required this.title,
    this.description,
    this.start,
    this.rrule,
  });

  final String uid;
  final String title;
  final String? description;
  final DateTime? start;
  final String? rrule;

  bool get isRecurring => rrule != null && rrule!.trim().isNotEmpty;

  /// Simple yearly rules (Google Calendar birthdays/anniversaries) can be
  /// imported as fixed-schedule yearly tasks.
  bool get isYearly =>
      isRecurring && rrule!.toUpperCase().contains('FREQ=YEARLY');
}

/// Parses VEVENTs out of .ics file content. Events without a summary are
/// skipped; missing UIDs get a synthetic one so dedupe still works.
List<IcsEvent> parseIcsEvents(String content) {
  final calendar = ICalendar.fromString(content);
  final events = <IcsEvent>[];
  for (final entry in calendar.data) {
    if (entry['type'] != 'VEVENT') continue;
    final title = _asString(entry['summary'])?.trim();
    if (title == null || title.isEmpty) continue;
    final start = _toDateTime(entry['dtstart']);
    final uid = _asString(entry['uid'])?.trim();
    events.add(IcsEvent(
      uid: (uid == null || uid.isEmpty)
          ? 'taskley-${title.hashCode}-${start?.millisecondsSinceEpoch ?? 0}'
          : uid,
      title: title,
      description: _asString(entry['description'])?.trim(),
      start: start,
      rrule: _asString(entry['rrule']),
    ));
  }
  events.sort((a, b) {
    final at = a.start, bt = b.start;
    if (at == null && bt == null) return a.title.compareTo(b.title);
    if (at == null) return 1;
    if (bt == null) return -1;
    return at.compareTo(bt);
  });
  return events;
}

String? _asString(dynamic value) {
  if (value == null) return null;
  if (value is String) return value;
  if (value is Map && value['value'] != null) return '${value['value']}';
  return '$value';
}

DateTime? _toDateTime(dynamic value) {
  if (value is IcsDateTime) {
    final dt = value.toDateTime();
    return dt == null ? null : (dt.isUtc ? dt.toLocal() : dt);
  }
  if (value is DateTime) return value.isUtc ? value.toLocal() : value;
  return null;
}
