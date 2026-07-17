import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/database.dart';
import '../../core/providers.dart';
import '../../core/recurrence/recurrence_engine.dart';
import '../../core/utils/date_utils.dart';
import 'ics_mapper.dart';

/// One-time migration from Google Calendar: pick an exported .ics file,
/// choose which events become tasks, import. Re-importing the same file
/// skips events that were already brought in.
class ImportIcsScreen extends ConsumerStatefulWidget {
  const ImportIcsScreen({super.key});

  @override
  ConsumerState<ImportIcsScreen> createState() => _ImportIcsScreenState();
}

class _ImportIcsScreenState extends ConsumerState<ImportIcsScreen> {
  List<IcsEvent>? _events;
  Set<String> _alreadyImported = {};
  final Set<String> _selected = {};
  bool _yearlyAsRecurring = true;
  int? _targetListId;
  bool _importing = false;

  Future<void> _pickFile() async {
    final messenger = ScaffoldMessenger.of(context);
    final result = await FilePicker.platform.pickFiles(withData: true);
    final file = result?.files.singleOrNull;
    if (file == null) return;
    final bytes = file.bytes;
    if (bytes == null) return;
    try {
      final events = parseIcsEvents(utf8.decode(bytes, allowMalformed: true));
      final imported = await ref.read(databaseProvider).importedEventUids();
      final now = DateTime.now();
      setState(() {
        _events = events;
        _alreadyImported = imported;
        _selected
          ..clear()
          // Preselect what's most likely wanted: not imported yet, and
          // either upcoming or a recurring event like a birthday.
          ..addAll(events
              .where((e) =>
                  !imported.contains(e.uid) &&
                  (e.isRecurring ||
                      (e.start != null && e.start!.isAfter(now))))
              .map((e) => e.uid));
      });
    } catch (e) {
      messenger.showSnackBar(
          SnackBar(content: Text('Could not read calendar file: $e')));
    }
  }

  Future<void> _import() async {
    final events = _events!;
    final db = ref.read(databaseProvider);
    final now = DateTime.now();
    setState(() => _importing = true);
    var count = 0;
    for (final event in events) {
      if (!_selected.contains(event.uid)) continue;
      final asYearly = event.isYearly && _yearlyAsRecurring;
      final anchor = event.start;

      DateTime? dueAt = anchor;
      if (asYearly && anchor != null && !anchor.isAfter(now)) {
        dueAt = nextFixed(
            anchor: anchor,
            interval: const RecurrenceInterval(1, IntervalUnit.year),
            after: now);
      }

      final notes = [
        if (event.description?.isNotEmpty ?? false) event.description!,
        if (event.isRecurring && !asYearly) 'Repeats (from calendar): ${event.rrule}',
      ].join('\n\n');

      final taskId = await db.insertTask(TasksCompanion.insert(
        title: event.title,
        listId: Value(_targetListId),
        notes: Value(notes.isEmpty ? null : notes),
        dueAt: Value(dueAt),
        recurrenceType: Value(
            asYearly ? RecurrenceType.fixedSchedule : RecurrenceType.none),
        intervalCount: Value(asYearly ? 1 : null),
        intervalUnit: Value(asYearly ? IntervalUnit.year : null),
        anchorDate: Value(asYearly ? (anchor ?? dueAt) : null),
      ));
      await db.recordImportedEvent(event.uid, taskId);
      count++;
    }
    if (!mounted) return;
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Imported $count task${count == 1 ? '' : 's'}')));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final events = _events;
    final lists = ref.watch(listsWithStatsProvider).valueOrNull ?? [];

    return Scaffold(
      appBar: AppBar(title: const Text('Import from Google Calendar')),
      body: events == null
          ? ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('How to export your calendar',
                            style: theme.textTheme.titleMedium),
                        const SizedBox(height: 8),
                        const Text(
                            '1. On a computer, open calendar.google.com\n'
                            '2. Settings → Import & export → Export\n'
                            '3. Unzip the download — each calendar is an .ics file\n'
                            '4. Copy the .ics file to this phone\n'
                            '5. Pick it below'),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _pickFile,
                  icon: const Icon(Icons.file_open),
                  label: const Text('Pick .ics file'),
                ),
              ],
            )
          : Column(
              children: [
                SwitchListTile(
                  title: const Text('Yearly events repeat every year'),
                  subtitle: const Text(
                      'Birthdays etc. become yearly recurring tasks'),
                  value: _yearlyAsRecurring,
                  onChanged: (v) => setState(() => _yearlyAsRecurring = v),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: DropdownButtonFormField<int?>(
                    initialValue: _targetListId,
                    decoration: const InputDecoration(
                        labelText: 'Add to list',
                        border: OutlineInputBorder()),
                    items: [
                      const DropdownMenuItem<int?>(
                          value: null, child: Text('No list')),
                      for (final l in lists)
                        DropdownMenuItem<int?>(
                            value: l.list.id, child: Text(l.list.name)),
                    ],
                    onChanged: (v) => setState(() => _targetListId = v),
                  ),
                ),
                Expanded(
                  child: events.isEmpty
                      ? const Center(child: Text('No events in this file'))
                      : ListView.builder(
                          itemCount: events.length,
                          itemBuilder: (context, i) {
                            final event = events[i];
                            final imported =
                                _alreadyImported.contains(event.uid);
                            return CheckboxListTile(
                              value: _selected.contains(event.uid),
                              onChanged: (checked) => setState(() {
                                if (checked == true) {
                                  _selected.add(event.uid);
                                } else {
                                  _selected.remove(event.uid);
                                }
                              }),
                              title: Text(event.title),
                              subtitle: Text([
                                if (event.start != null)
                                  formatDue(event.start!),
                                if (event.isYearly)
                                  'Yearly'
                                else if (event.isRecurring)
                                  'Recurring',
                                if (imported) 'Already imported',
                              ].join('  ·  ')),
                              secondary: event.isRecurring
                                  ? const Icon(Icons.event_repeat)
                                  : null,
                            );
                          },
                        ),
                ),
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        OutlinedButton(
                          onPressed: _importing ? null : _pickFile,
                          child: const Text('Other file'),
                        ),
                        const Spacer(),
                        FilledButton.icon(
                          onPressed: _selected.isEmpty || _importing
                              ? null
                              : _import,
                          icon: _importing
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2))
                              : const Icon(Icons.download_done),
                          label: Text('Import ${_selected.length}'),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
