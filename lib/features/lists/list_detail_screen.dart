import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/database.dart';
import '../../core/providers.dart';
import '../tasks/task_actions.dart';
import '../tasks/task_editor_sheet.dart';
import '../tasks/task_tile.dart';

/// A single checklist: open items, a collapsible "Completed" section, and a
/// quick-add field pinned above the keyboard.
class ListDetailScreen extends ConsumerStatefulWidget {
  const ListDetailScreen({super.key, required this.listId});

  final int listId;

  @override
  ConsumerState<ListDetailScreen> createState() => _ListDetailScreenState();
}

/// Open items with long-press drag-to-reorder; keeps a local copy so the row
/// moves instantly while the new order is persisted.
class _ReorderableOpenTasks extends ConsumerStatefulWidget {
  const _ReorderableOpenTasks({required this.tasks});

  final List<Task> tasks;

  @override
  ConsumerState<_ReorderableOpenTasks> createState() =>
      _ReorderableOpenTasksState();
}

class _ReorderableOpenTasksState extends ConsumerState<_ReorderableOpenTasks> {
  late List<Task> _tasks = widget.tasks;

  @override
  void didUpdateWidget(_ReorderableOpenTasks oldWidget) {
    super.didUpdateWidget(oldWidget);
    _tasks = widget.tasks;
  }

  @override
  Widget build(BuildContext context) {
    return ReorderableListView(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      onReorderItem: (oldIndex, newIndex) {
        setState(() {
          final moved = _tasks.removeAt(oldIndex);
          _tasks.insert(newIndex, moved);
        });
        ref
            .read(databaseProvider)
            .reorderTasks([for (final t in _tasks) t.id]);
      },
      children: [
        for (final task in _tasks)
          TaskTile(key: ValueKey('open-${task.id}'), task: task),
      ],
    );
  }
}

class _ListDetailScreenState extends ConsumerState<ListDetailScreen> {
  final TextEditingController _quickAdd = TextEditingController();
  bool _showCompleted = true;

  @override
  void dispose() {
    _quickAdd.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tasksAsync = ref.watch(tasksInListProvider(widget.listId));
    final listAsync = ref.watch(listProvider(widget.listId));
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(listAsync.valueOrNull?.name ?? ''),
        actions: [
          IconButton(
            tooltip: 'Add detailed task',
            icon: const Icon(Icons.add_task),
            onPressed: () =>
                showTaskEditor(context, initialListId: widget.listId),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: tasksAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('$e')),
              data: (tasks) {
                final open = tasks.where((t) => !t.isDone).toList();
                final done = tasks.where((t) => t.isDone).toList();
                if (tasks.isEmpty) {
                  return Center(
                    child: Text(
                      'Empty list — add an item below.',
                      style: theme.textTheme.bodyLarge!
                          .copyWith(color: theme.colorScheme.outline),
                    ),
                  );
                }
                return ListView(
                  children: [
                    _ReorderableOpenTasks(tasks: open),
                    if (done.isNotEmpty) ...[
                      InkWell(
                        onTap: () =>
                            setState(() => _showCompleted = !_showCompleted),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                          child: Row(
                            children: [
                              Text('Completed (${done.length})',
                                  style: theme.textTheme.titleSmall),
                              Icon(
                                _showCompleted
                                    ? Icons.expand_less
                                    : Icons.expand_more,
                                size: 18,
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (_showCompleted)
                        for (final task in done) TaskTile(task: task),
                    ],
                  ],
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: TextField(
                controller: _quickAdd,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  hintText: 'Add item',
                  prefixIcon: const Icon(Icons.add),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(28)),
                  isDense: true,
                ),
                onSubmitted: (value) async {
                  final title = value.trim();
                  if (title.isEmpty) return;
                  await ref
                      .read(taskActionsProvider)
                      .addChecklistItem(widget.listId, title);
                  _quickAdd.clear();
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
