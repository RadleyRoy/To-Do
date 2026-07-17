import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/utils/date_utils.dart';
import '../tasks/task_tile.dart';

enum SmartView { today, upcoming }

/// "Today" (incl. overdue) and "Upcoming" task lists, grouped by day.
class SmartViewScreen extends ConsumerWidget {
  const SmartViewScreen({super.key, required this.view});

  final SmartView view;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasksAsync = ref.watch(view == SmartView.today
        ? todayTasksProvider
        : upcomingTasksProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar:
          AppBar(title: Text(view == SmartView.today ? 'Today' : 'Upcoming')),
      body: tasksAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (tasks) {
          if (tasks.isEmpty) {
            return Center(
              child: Text(
                view == SmartView.today
                    ? 'Nothing due today 🎉'
                    : 'Nothing planned yet',
                style: theme.textTheme.bodyLarge!
                    .copyWith(color: theme.colorScheme.outline),
              ),
            );
          }
          final children = <Widget>[];
          DateTime? currentDay;
          for (final task in tasks) {
            final day = dateOnly(task.dueAt!);
            if (currentDay == null || day != currentDay) {
              currentDay = day;
              children.add(Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                child: Text(
                  _header(day),
                  style: theme.textTheme.titleSmall!
                      .copyWith(color: theme.colorScheme.primary),
                ),
              ));
            }
            children.add(TaskTile(task: task));
          }
          return ListView(children: children);
        },
      ),
    );
  }

  String _header(DateTime day) {
    if (view == SmartView.today && day.isBefore(dateOnly(DateTime.now()))) {
      return 'Overdue — ${formatDayHeader(day)}';
    }
    return formatDayHeader(day);
  }
}
