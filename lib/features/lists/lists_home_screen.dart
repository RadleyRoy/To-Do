import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/database.dart';
import '../../core/providers.dart';
import '../tasks/task_editor_sheet.dart';
import 'list_detail_screen.dart';
import 'smart_view_screen.dart';

class ListsHomeScreen extends ConsumerWidget {
  const ListsHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lists = ref.watch(listsWithStatsProvider);
    final todayCount =
        ref.watch(todayTasksProvider).valueOrNull?.length ?? 0;
    final upcomingCount =
        ref.watch(upcomingTasksProvider).valueOrNull?.length ?? 0;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Taskley')),
      floatingActionButton: FloatingActionButton(
        heroTag: 'home-fab',
        onPressed: () => _showCreateMenu(context, ref),
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              children: [
                _SmartTile(
                  icon: Icons.today,
                  color: theme.colorScheme.primary,
                  title: 'Today',
                  count: todayCount,
                  onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const SmartViewScreen(
                              view: SmartView.today))),
                ),
                _SmartTile(
                  icon: Icons.upcoming,
                  color: theme.colorScheme.tertiary,
                  title: 'Upcoming',
                  count: upcomingCount,
                  onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const SmartViewScreen(
                              view: SmartView.upcoming))),
                ),
                const Divider(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                  child: Text('My lists', style: theme.textTheme.titleSmall),
                ),
                switch (lists) {
                  AsyncData(:final value) when value.isEmpty => Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'No lists yet. Tap + to create one.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium!
                            .copyWith(color: theme.colorScheme.outline),
                      ),
                    ),
                  AsyncData(:final value) => _ReorderableLists(entries: value),
                  _ => const Center(child: CircularProgressIndicator()),
                },
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                'created by Radley',
                style: theme.textTheme.bodySmall!
                    .copyWith(color: theme.colorScheme.outline),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showCreateMenu(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.add_task),
              title: const Text('New task'),
              subtitle: const Text('With date, alarm, or recurrence'),
              onTap: () {
                Navigator.pop(sheetContext);
                showTaskEditor(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.playlist_add),
              title: const Text('New list'),
              subtitle: const Text('A checklist of items'),
              onTap: () {
                Navigator.pop(sheetContext);
                promptListName(context, ref);
              },
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> promptListName(BuildContext context, WidgetRef ref,
    {TaskList? existing}) async {
  final controller = TextEditingController(text: existing?.name ?? '');
  final name = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(existing == null ? 'New list' : 'Rename list'),
      content: TextField(
        controller: controller,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(hintText: 'List name'),
        onSubmitted: (v) => Navigator.pop(context, v),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: Text(existing == null ? 'Create' : 'Rename')),
      ],
    ),
  );
  final trimmed = name?.trim() ?? '';
  if (trimmed.isEmpty) return;
  final db = ref.read(databaseProvider);
  if (existing == null) {
    await db.createList(trimmed);
  } else {
    await db.renameList(existing.id, trimmed);
  }
}

/// The user's lists with long-press drag-to-reorder. Keeps a local copy so
/// the row moves instantly while the new order is persisted.
class _ReorderableLists extends ConsumerStatefulWidget {
  const _ReorderableLists({required this.entries});

  final List<ListWithStats> entries;

  @override
  ConsumerState<_ReorderableLists> createState() => _ReorderableListsState();
}

class _ReorderableListsState extends ConsumerState<_ReorderableLists> {
  late List<ListWithStats> _entries = widget.entries;

  @override
  void didUpdateWidget(_ReorderableLists oldWidget) {
    super.didUpdateWidget(oldWidget);
    _entries = widget.entries;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ReorderableListView(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      buildDefaultDragHandles: true,
      onReorderItem: (oldIndex, newIndex) {
        setState(() {
          final moved = _entries.removeAt(oldIndex);
          _entries.insert(newIndex, moved);
        });
        ref
            .read(databaseProvider)
            .reorderLists([for (final e in _entries) e.list.id]);
      },
      children: [
        for (final entry in _entries)
          ListTile(
            key: ValueKey('list-${entry.list.id}'),
            leading: Icon(Icons.list_alt, color: theme.colorScheme.secondary),
            title: Text(entry.list.name),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('${entry.doneTasks}/${entry.totalTasks}',
                    style: theme.textTheme.bodySmall),
                PopupMenuButton<String>(
                  onSelected: (choice) => switch (choice) {
                    'rename' =>
                        promptListName(context, ref, existing: entry.list),
                    _ => _confirmDeleteList(context, entry.list),
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(value: 'rename', child: Text('Rename')),
                    PopupMenuItem(value: 'delete', child: Text('Delete')),
                  ],
                ),
              ],
            ),
            onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => ListDetailScreen(listId: entry.list.id))),
          ),
      ],
    );
  }

  Future<void> _confirmDeleteList(BuildContext context, TaskList list) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete "${list.name}"?'),
        content: const Text('All tasks in this list will be deleted.'),
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
    if (confirmed == true) {
      await ref.read(databaseProvider).deleteList(list.id);
    }
  }
}

class _SmartTile extends StatelessWidget {
  const _SmartTile(
      {required this.icon,
      required this.color,
      required this.title,
      required this.count,
      required this.onTap});

  final IconData icon;
  final Color color;
  final String title;
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(title),
      trailing: count == 0 ? null : Badge.count(count: count),
      onTap: onTap,
    );
  }
}
