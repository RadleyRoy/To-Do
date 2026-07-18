import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/db/database.dart';
import '../../core/providers.dart';
import '../../core/theme/app_styles.dart';
import '../../core/utils/date_utils.dart';
import '../tasks/task_editor_sheet.dart';
import 'list_detail_screen.dart';
import 'smart_view_screen.dart';

class ListsHomeScreen extends ConsumerWidget {
  const ListsHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lists = ref.watch(listsWithStatsProvider);
    final todayTasks =
        ref.watch(todayTasksProvider).valueOrNull ?? const <Task>[];
    final upcomingTasks =
        ref.watch(upcomingTasksProvider).valueOrNull ?? const <Task>[];
    final theme = Theme.of(context);

    // Say something useful under each count rather than repeating the label.
    final startOfToday = dateOnly(DateTime.now());
    final overdue =
        todayTasks.where((t) => t.dueAt!.isBefore(startOfToday)).length;
    final todayCaption = switch ((todayTasks.length, overdue)) {
      (0, _) => 'All clear',
      (_, > 0) => '$overdue overdue',
      _ => 'next at ${DateFormat.Hm().format(todayTasks.first.dueAt!)}',
    };
    final upcomingCaption = upcomingTasks.isEmpty
        ? 'Nothing planned'
        : formatDue(upcomingTasks.first.dueAt!);

    return Scaffold(
      floatingActionButton: FloatingActionButton(
        heroTag: 'home-fab',
        onPressed: () => _showCreateMenu(context, ref),
        child: const Icon(Icons.add),
      ),
      body: SafeArea(
        bottom: false,
        child: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              sliver: SliverList.list(children: [
            _Greeting(),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: _SummaryCard(
                    icon: Icons.wb_sunny_outlined,
                    label: 'Today',
                    count: todayTasks.length,
                    caption: todayCaption,
                    background: theme.colorScheme.primaryContainer,
                    foreground: theme.colorScheme.onPrimaryContainer,
                    onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) =>
                                const SmartViewScreen(view: SmartView.today))),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _SummaryCard(
                    icon: Icons.event_outlined,
                    label: 'Upcoming',
                    count: upcomingTasks.length,
                    caption: upcomingCaption,
                    background: theme.colorScheme.tertiaryContainer,
                    foreground: theme.colorScheme.onTertiaryContainer,
                    onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const SmartViewScreen(
                                view: SmartView.upcoming))),
                  ),
                ),
              ],
            ),
            AppStyles.sectionGap,
            const SectionLabel('My lists'),
            AppStyles.labelGap,
            switch (lists) {
              AsyncData(:final value) when value.isEmpty => const SizedBox(),
              AsyncData(:final value) => _ReorderableLists(entries: value),
              AsyncError(:final error) => Text('$error'),
              _ => const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                ),
            },
            _NewListCard(onTap: () => promptListName(context, ref)),
              ]),
            ),
            // Keeps the credit at the bottom of the screen when the lists are
            // short, and below them when they scroll.
            SliverFillRemaining(
              hasScrollBody: false,
              child: Padding(
                padding: const EdgeInsets.only(top: 28, bottom: 24),
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: Text(
                    'created by Radley',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.outline),
                  ),
                ),
              ),
            ),
          ],
        ),
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
              subtitle: const Text('With date, notification, or recurrence'),
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

/// "Good evening" over today's date.
class _Greeting extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final now = DateTime.now();
    final greeting = switch (now.hour) {
      < 12 => 'Good morning',
      < 17 => 'Good afternoon',
      _ => 'Good evening',
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(greeting,
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        const SizedBox(height: 2),
        Text(
          DateFormat('EEEE, d MMMM').format(now),
          style: theme.textTheme.headlineSmall
              ?.copyWith(fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}

/// Tonal card showing a count for one of the smart views.
class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.icon,
    required this.label,
    required this.count,
    required this.caption,
    required this.background,
    required this.foreground,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final int count;
  final String caption;
  final Color background;
  final Color foreground;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: background,
      borderRadius: AppStyles.cardRadius,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: AppStyles.cardPadding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: foreground, size: 22),
              const SizedBox(height: 14),
              Text(
                '$count',
                style: theme.textTheme.displaySmall?.copyWith(
                    color: foreground, fontWeight: FontWeight.w700, height: 1),
              ),
              const SizedBox(height: 4),
              Text(label,
                  style: theme.textTheme.titleSmall?.copyWith(
                      color: foreground, fontWeight: FontWeight.w600)),
              Text(
                caption,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: foreground.withValues(alpha: 0.75)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A list as a card: name, progress bar, and completed/total.
class _ListCard extends StatelessWidget {
  const _ListCard({
    required this.entry,
    required this.onTap,
    required this.onRename,
    required this.onDelete,
  });

  final ListWithStats entry;
  final VoidCallback onTap;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final total = entry.totalTasks;
    final done = entry.doneTasks;
    final progress = total == 0 ? 0.0 : done / total;
    final complete = total > 0 && done == total;

    return Material(
      color: theme.colorScheme.surfaceContainerHigh,
      borderRadius: AppStyles.cardRadius,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 8, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      entry.list.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                  if (complete)
                    Icon(Icons.check_circle,
                        size: 18, color: theme.colorScheme.primary)
                  else
                    Text('$done/$total',
                        style: theme.textTheme.labelMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant)),
                  PopupMenuButton<String>(
                    tooltip: 'List options',
                    onSelected: (choice) =>
                        choice == 'rename' ? onRename() : onDelete(),
                    itemBuilder: (context) => const [
                      PopupMenuItem(value: 'rename', child: Text('Rename')),
                      PopupMenuItem(value: 'delete', child: Text('Delete')),
                    ],
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: total == 0
                    ? Text('No items yet',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: theme.colorScheme.outline))
                    : ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: progress,
                          minHeight: 6,
                          backgroundColor: theme.colorScheme.surfaceContainerHighest,
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Outlined "add" card that closes off the list section.
class _NewListCard extends StatelessWidget {
  const _NewListCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: Colors.transparent,
      borderRadius: AppStyles.cardRadius,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: AppStyles.cardRadius,
            border: Border.all(color: theme.colorScheme.outlineVariant),
          ),
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.add, size: 20, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Text('New list',
                  style: theme.textTheme.titleSmall?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w600)),
            ],
          ),
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
    return ReorderableListView(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      onReorderItem: (oldIndex, newIndex) {
        setState(() {
          final moved = _entries.removeAt(oldIndex);
          _entries.insert(newIndex, moved);
        });
        ref
            .read(databaseProvider)
            .reorderLists([for (final e in _entries) e.list.id]);
      },
      proxyDecorator: (child, index, animation) => Material(
        color: Colors.transparent,
        borderRadius: AppStyles.cardRadius,
        elevation: 6,
        child: child,
      ),
      children: [
        for (final entry in _entries)
          Padding(
            key: ValueKey('list-${entry.list.id}'),
            padding: const EdgeInsets.only(bottom: 10),
            child: _ListCard(
              entry: entry,
              onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => ListDetailScreen(listId: entry.list.id))),
              onRename: () =>
                  promptListName(context, ref, existing: entry.list),
              onDelete: () => _confirmDeleteList(context, entry.list),
            ),
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
