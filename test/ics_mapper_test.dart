import 'package:flutter_test/flutter_test.dart';
import 'package:taskley/features/import_ics/ics_mapper.dart';

const _sampleIcs = '''
BEGIN:VCALENDAR
VERSION:2.0
PRODID:-//Google Inc//Google Calendar 70.9054//EN
CALSCALE:GREGORIAN
BEGIN:VEVENT
DTSTART:20260801T100000Z
DTEND:20260801T110000Z
UID:abc123@google.com
SUMMARY:Dentist appointment
DESCRIPTION:Bring insurance card
END:VEVENT
BEGIN:VEVENT
DTSTART;VALUE=DATE:19900512
RRULE:FREQ=YEARLY
UID:bday456@google.com
SUMMARY:Mom's birthday
END:VEVENT
BEGIN:VEVENT
DTSTART:20260901T090000Z
RRULE:FREQ=WEEKLY;BYDAY=MO
UID:weekly789@google.com
SUMMARY:Team standup
END:VEVENT
END:VCALENDAR
''';

void main() {
  test('parses VEVENTs sorted by start date', () {
    final events = parseIcsEvents(_sampleIcs);
    expect(events.map((e) => e.uid), [
      'bday456@google.com',
      'abc123@google.com',
      'weekly789@google.com',
    ]);
  });

  test('extracts fields and converts UTC to local time', () {
    final dentist = parseIcsEvents(_sampleIcs)
        .singleWhere((e) => e.uid == 'abc123@google.com');
    expect(dentist.title, 'Dentist appointment');
    expect(dentist.description, 'Bring insurance card');
    expect(dentist.start, DateTime.utc(2026, 8, 1, 10).toLocal());
    expect(dentist.start!.isUtc, isFalse);
    expect(dentist.isRecurring, isFalse);
  });

  test('classifies yearly vs other recurrence', () {
    final events = parseIcsEvents(_sampleIcs);
    final birthday = events.singleWhere((e) => e.uid == 'bday456@google.com');
    final standup = events.singleWhere((e) => e.uid == 'weekly789@google.com');

    expect(birthday.isYearly, isTrue);
    expect(birthday.start, DateTime(1990, 5, 12));

    expect(standup.isRecurring, isTrue);
    expect(standup.isYearly, isFalse);
  });

  test('skips events without a summary', () {
    const ics = '''
BEGIN:VCALENDAR
VERSION:2.0
PRODID:-//Test//EN
BEGIN:VEVENT
DTSTART:20260801T100000Z
UID:no-title@test
END:VEVENT
END:VCALENDAR
''';
    expect(parseIcsEvents(ics), isEmpty);
  });
}
