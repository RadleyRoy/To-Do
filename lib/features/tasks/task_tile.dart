import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/database.dart';
import '../../core/providers.dart';
import '../../core/recurrence/recurrence_engine.dart';
import '../../core/utils/date_utils.dart';
import 'task_actions.dart';
import 'task_editor_sheet.dart';

/// One task row: checkbox, title, due/recurrence/alarm details. Completing a
/// recurring task shows the recalculated next due date with an Undo action.
class TaskTile extends ConsumerWidget {
  const TaskTile({super.key, required this.task, this.showDue = true});

  final Task task;
  final bool showDue;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final subtasks = ref.watch(subtasksProvider(task.id)).valueOrNull;
    final theme = Theme.of(context);
    final overdue = !task.isDone &&
        task.dueAt != null &&
        task.dueAt!.isBefore(DateTime.now());

    return Dismissible(
      key: ValueKey('task-${task.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        color: theme.colorScheme.errorContainer,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        child: Icon(Icons.delete_outline,
            color: theme.colorScheme.onErrorContainer),
      ),
      onDismissed: (_) => _delete(context, ref),
      child: ListTile(
        leading: Checkbox(
          value: task.isDone,
          shape: const CircleBorder(),
          onChanged: (checked) => checked == true
              ? _complete(context, ref)
              : _uncomplete(context, ref),
        ),
        title: Text(
          task.title,
          style: task.isDone
              ? TextStyle(
                  decoration: TextDecoration.lineThrough,
                  color: theme.colorScheme.outline)
              : null,
        ),
        subtitle: _subtitle(theme, subtasks, overdue),
        onTap: () => showTaskEditor(context, task: task),
      ),
    );
  }

  Widget? _subtitle(ThemeData theme, List<Subtask>? subtasks, bool overdue) {
    final parts = <InlineSpan>[];
    void addText(String text, {Color? color}) {
      if (parts.isNotEmpty) parts.add(const TextSpan(text: '  ·  '));
      parts.add(TextSpan(text: text, style: TextStyle(color: color)));
    }

    void addIconText(IconData icon, String text, {Color? color}) {
      if (parts.isNotEmpty) parts.add(const TextSpan(text: '  ·  '));
      parts.add(WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: Icon(icon, size: 14, color: color ?? theme.colorScheme.outline),
      ));
      parts.add(TextSpan(text: ' $text', style: TextStyle(color: color)));
    }

    if (showDue && task.dueAt != null) {
      addText(formatDue(task.dueAt!),
          color: overdue ? theme.colorScheme.error : null);
    }
    if (task.recurrenceType != RecurrenceType.none) {
      final interval =
          RecurrenceInterval(task.intervalCount ?? 1, task.intervalUnit ?? IntervalUnit.day);
      addIconText(
          task.recurrenceType == RecurrenceType.fixedSchedule
              ? Icons.event_repeat
              : Icons.autorenew,
          interval.describe());
    }
    if (task.snoozedUntil != null &&
        task.snoozedUntil!.isAfter(DateTime.now())) {
      addIconText(Icons.snooze, formatDue(task.snoozedUntil!),
          color: theme.colorScheme.tertiary);
    } else if (task.hasAlarm && !task.isDone) {
      addIconText(Icons.alarm, '');
    }
    if (subtasks != null && subtasks.isNotEmpty) {
      addText('${subtasks.where((s) => s.isDone).length}/${subtasks.length}');
    }
    if (task.notes?.trim().isNotEmpty ?? false) {
      addIconText(Icons.notes, '');
    }
    if (parts.isEmpty) return null;
    return Text.rich(TextSpan(children: parts), maxLines: 1);
  }

  Future<void> _complete(BuildContext context, WidgetRef ref) async {
    final actions = ref.read(taskActionsProvider);
    final messenger = ScaffoldMessenger.of(context);
    final updated = await actions.complete(task);
    final recurring = task.recurrenceType != RecurrenceType.none;
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(
      content: Text(recurring && updated.dueAt != null
          ? 'Done — next: ${formatDue(updated.dueAt!)}'
          : 'Completed "${task.title}"'),
      action: SnackBarAction(
        label: 'Undo',
        onPressed: () => actions.uncomplete(updated),
      ),
    ));
  }

  Future<void> _uncomplete(BuildContext context, WidgetRef ref) =>
      ref.read(taskActionsProvider).uncomplete(task);

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    await ref.read(taskActionsProvider).delete(task);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(content: Text('Deleted "${task.title}"')));
  }
}
