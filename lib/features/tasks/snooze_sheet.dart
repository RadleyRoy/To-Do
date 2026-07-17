import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/database.dart';
import '../../core/utils/date_utils.dart';
import 'task_actions.dart';

const snoozeChoices = [
  (label: '15 minutes', duration: Duration(minutes: 15)),
  (label: '1 hour', duration: Duration(hours: 1)),
  (label: '1 day', duration: Duration(days: 1)),
  (label: '1 week', duration: Duration(days: 7)),
];

/// Picker opened by a reminder's Snooze button: reschedules the alarm to
/// now + the chosen duration (the due date itself doesn't move).
Future<void> showSnoozeSheet(
    BuildContext context, WidgetRef ref, Task task) async {
  final duration = await showModalBottomSheet<Duration>(
    context: context,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'Snooze "${task.title}" for…',
              style: Theme.of(sheetContext).textTheme.titleMedium,
            ),
          ),
          for (final choice in snoozeChoices)
            ListTile(
              leading: const Icon(Icons.snooze),
              title: Text(choice.label),
              onTap: () => Navigator.pop(sheetContext, choice.duration),
            ),
        ],
      ),
    ),
  );
  if (duration == null) return;
  final updated = await ref.read(taskActionsProvider).snooze(task, duration);
  if (context.mounted && updated.snoozedUntil != null) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content:
            Text('Snoozed — rings ${formatDue(updated.snoozedUntil!)}')));
  }
}
