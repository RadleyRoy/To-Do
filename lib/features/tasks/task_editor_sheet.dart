import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/database.dart';
import '../../core/providers.dart';
import '../../core/recurrence/recurrence_engine.dart';
import '../../core/utils/date_utils.dart';
import 'task_actions.dart';

/// Opens the task editor. Pass [task] to edit, or [initialListId] /
/// [initialDueDate] to preset fields on a new task.
Future<void> showTaskEditor(
  BuildContext context, {
  Task? task,
  int? initialListId,
  DateTime? initialDueDate,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => TaskEditorSheet(
        task: task, initialListId: initialListId, initialDueDate: initialDueDate),
  );
}

class TaskEditorSheet extends ConsumerStatefulWidget {
  const TaskEditorSheet(
      {super.key, this.task, this.initialListId, this.initialDueDate});

  final Task? task;
  final int? initialListId;
  final DateTime? initialDueDate;

  @override
  ConsumerState<TaskEditorSheet> createState() => _TaskEditorSheetState();
}

class _TaskEditorSheetState extends ConsumerState<TaskEditorSheet> {
  late final TextEditingController _title;
  late final TextEditingController _notes;
  final TextEditingController _newSubtask = TextEditingController();
  final TextEditingController _intervalCount = TextEditingController();

  int? _listId;
  DateTime? _dueDate; // date part
  TimeOfDay? _dueTime;
  bool _hasAlarm = false;
  RecurrenceType _recurrence = RecurrenceType.none;
  IntervalUnit _intervalUnit = IntervalUnit.month;
  List<SubtaskDraft> _subtasks = [];
  bool _loadedSubtasks = false;

  @override
  void initState() {
    super.initState();
    final task = widget.task;
    _title = TextEditingController(text: task?.title ?? '');
    _notes = TextEditingController(text: task?.notes ?? '');
    _listId = task != null ? task.listId : widget.initialListId;
    final due = task?.dueAt ?? widget.initialDueDate;
    if (due != null) {
      _dueDate = dateOnly(due);
      if (due.hour != 0 || due.minute != 0) {
        _dueTime = TimeOfDay(hour: due.hour, minute: due.minute);
      }
    }
    _hasAlarm = task?.hasAlarm ?? false;
    _recurrence = task?.recurrenceType ?? RecurrenceType.none;
    _intervalUnit = task?.intervalUnit ?? IntervalUnit.month;
    _intervalCount.text = '${task?.intervalCount ?? 1}';
    if (task != null) {
      ref.read(databaseProvider).getSubtasks(task.id).then((subs) {
        if (!mounted) return;
        setState(() {
          _subtasks = [
            for (final s in subs)
              SubtaskDraft(id: s.id, title: s.title, isDone: s.isDone)
          ];
          _loadedSubtasks = true;
        });
      });
    } else {
      _loadedSubtasks = true;
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _notes.dispose();
    _newSubtask.dispose();
    _intervalCount.dispose();
    super.dispose();
  }

  DateTime? get _dueAt {
    final date = _dueDate;
    if (date == null) return null;
    final time = _dueTime;
    return DateTime(date.year, date.month, date.day, time?.hour ?? 0,
        time?.minute ?? 0);
  }

  @override
  Widget build(BuildContext context) {
    final lists = ref.watch(listsWithStatsProvider).valueOrNull ?? [];
    final theme = Theme.of(context);
    final editing = widget.task != null;

    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.85,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (context, scrollController) => ListView(
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(editing ? 'Edit task' : 'New task',
                      style: theme.textTheme.titleLarge),
                ),
                if (editing)
                  IconButton(
                    tooltip: 'Delete task',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: _confirmDelete,
                  ),
                FilledButton(onPressed: _save, child: const Text('Save')),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _title,
              autofocus: !editing,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                  labelText: 'Title', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _notes,
              maxLines: 3,
              minLines: 1,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                  labelText: 'Notes', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int?>(
              initialValue: _listId,
              decoration: const InputDecoration(
                  labelText: 'List', border: OutlineInputBorder()),
              items: [
                const DropdownMenuItem<int?>(
                    value: null, child: Text('No list')),
                for (final l in lists)
                  DropdownMenuItem<int?>(value: l.list.id, child: Text(l.list.name)),
              ],
              onChanged: (v) => setState(() => _listId = v),
            ),
            const SizedBox(height: 16),
            Text('Schedule', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                InputChip(
                  avatar: const Icon(Icons.event, size: 18),
                  label: Text(_dueDate == null
                      ? 'Add date'
                      : formatDue(_dueDate!)),
                  onPressed: _pickDate,
                  onDeleted: _dueDate == null
                      ? null
                      : () => setState(() {
                            _dueDate = null;
                            _dueTime = null;
                            _hasAlarm = false;
                            _recurrence = RecurrenceType.none;
                          }),
                ),
                InputChip(
                  avatar: const Icon(Icons.schedule, size: 18),
                  label: Text(_dueTime == null
                      ? 'Add time'
                      : _dueTime!.format(context)),
                  onPressed: _pickTime,
                  onDeleted: _dueTime == null
                      ? null
                      : () => setState(() => _dueTime = null),
                ),
              ],
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Alarm'),
              subtitle: Text(_dueDate == null
                  ? 'Set a date first'
                  : _dueTime == null
                      ? 'Rings at midnight — add a time'
                      : 'Rings at the scheduled time'),
              value: _hasAlarm,
              onChanged: _dueDate == null
                  ? null
                  : (v) => setState(() => _hasAlarm = v),
            ),
            const SizedBox(height: 8),
            Text('Repeat', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            SegmentedButton<RecurrenceType>(
              segments: const [
                ButtonSegment(
                    value: RecurrenceType.none, label: Text('Once')),
                ButtonSegment(
                    value: RecurrenceType.afterCompletion,
                    label: Text('After done')),
                ButtonSegment(
                    value: RecurrenceType.fixedSchedule,
                    label: Text('Fixed')),
              ],
              selected: {_recurrence},
              onSelectionChanged: (s) => setState(() => _recurrence = s.first),
            ),
            if (_recurrence != RecurrenceType.none) ...[
              const SizedBox(height: 8),
              Text(
                _recurrence == RecurrenceType.afterCompletion
                    ? 'Next due is counted from the day you complete it (e.g. car service).'
                    : 'Follows the calendar from the first date, even if you finish late (e.g. birthdays).',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Text('Every'),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 64,
                    child: TextField(
                      controller: _intervalCount,
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.center,
                      decoration:
                          const InputDecoration(border: OutlineInputBorder()),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<IntervalUnit>(
                      initialValue: _intervalUnit,
                      decoration: const InputDecoration(
                          border: OutlineInputBorder()),
                      items: const [
                        DropdownMenuItem(
                            value: IntervalUnit.day, child: Text('days')),
                        DropdownMenuItem(
                            value: IntervalUnit.week, child: Text('weeks')),
                        DropdownMenuItem(
                            value: IntervalUnit.month, child: Text('months')),
                        DropdownMenuItem(
                            value: IntervalUnit.year, child: Text('years')),
                      ],
                      onChanged: (v) =>
                          setState(() => _intervalUnit = v ?? _intervalUnit),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 16),
            Text('Subtasks', style: theme.textTheme.titleSmall),
            if (!_loadedSubtasks)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              ),
            for (final (i, sub) in _subtasks.indexed)
              Row(
                key: ValueKey('draft-$i-${sub.id}'),
                children: [
                  Checkbox(
                    value: sub.isDone,
                    shape: const CircleBorder(),
                    onChanged: (v) =>
                        setState(() => sub.isDone = v ?? false),
                  ),
                  Expanded(
                    child: TextFormField(
                      initialValue: sub.title,
                      onChanged: (v) => sub.title = v,
                      decoration: const InputDecoration(
                          isDense: true, border: InputBorder.none),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () => setState(() => _subtasks.removeAt(i)),
                  ),
                ],
              ),
            TextField(
              controller: _newSubtask,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.add),
                hintText: 'Add subtask',
                border: InputBorder.none,
              ),
              onSubmitted: (v) {
                final title = v.trim();
                if (title.isEmpty) return;
                setState(() {
                  _subtasks.add(SubtaskDraft(title: title));
                  _newSubtask.clear();
                });
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _dueDate ?? now,
      firstDate: DateTime(now.year - 10),
      lastDate: DateTime(now.year + 50),
    );
    if (picked != null) setState(() => _dueDate = picked);
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _dueTime ?? const TimeOfDay(hour: 9, minute: 0),
    );
    if (picked != null) {
      setState(() {
        _dueTime = picked;
        _dueDate ??= dateOnly(DateTime.now());
      });
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context)
      ..removeCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    if (title.isEmpty) {
      _showError('Give the task a title');
      return;
    }
    if (_listId == null && _dueAt == null) {
      _showError('Pick a list or set a date');
      return;
    }
    RecurrenceInterval? interval;
    if (_recurrence != RecurrenceType.none) {
      if (_dueAt == null) {
        _showError('Recurring tasks need a date');
        return;
      }
      final count = int.tryParse(_intervalCount.text.trim());
      if (count == null || count < 1) {
        _showError('Repeat interval must be a positive number');
        return;
      }
      interval = RecurrenceInterval(count, _intervalUnit);
    }

    // Keep drafts the user typed but didn't submit with the + field.
    final pending = _newSubtask.text.trim();
    if (pending.isNotEmpty) _subtasks.add(SubtaskDraft(title: pending));

    final navigator = Navigator.of(context);
    await ref.read(taskActionsProvider).saveTask(
          id: widget.task?.id,
          title: title,
          notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
          listId: _listId,
          dueAt: _dueAt,
          hasAlarm: _hasAlarm,
          recurrenceType: _recurrence,
          interval: interval,
          subtasks: _subtasks,
        );
    if (mounted) navigator.pop();
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete task?'),
        content: Text('"${widget.task!.title}" will be removed permanently.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final navigator = Navigator.of(context);
    await ref.read(taskActionsProvider).delete(widget.task!);
    if (mounted) navigator.pop();
  }
}
