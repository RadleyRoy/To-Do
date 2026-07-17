import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';
import 'package:intl/intl.dart';

import '../db/database.dart';

/// Pushes today's tasks into the home-screen widget. Safe to call from the
/// notification background isolate; a no-op where the plugin is unavailable
/// (tests).
class HomeWidgetService {
  Future<void> refresh(AppDatabase db) async {
    try {
      final now = DateTime.now();
      final tasks = await db.watchTodayAndOverdue(now).first;
      final lines = tasks.take(6).map((t) {
        final due = t.dueAt!;
        final time = due.hour == 0 && due.minute == 0
            ? ''
            : '${DateFormat.Hm().format(due)}  ';
        final overdue =
            due.isBefore(DateTime(now.year, now.month, now.day)) ? '⚠ ' : '';
        return '$overdue$time${t.title}';
      }).join('\n');
      final extra = tasks.length - 6;

      await HomeWidget.saveWidgetData<String>('today_count', '${tasks.length}');
      await HomeWidget.saveWidgetData<String>(
          'today_tasks',
          tasks.isEmpty
              ? 'Nothing due today 🎉'
              : extra > 0
                  ? '$lines\n+$extra more'
                  : lines);
      await HomeWidget.updateWidget(
        name: 'TaskleyWidgetProvider',
        qualifiedAndroidName: 'com.radley.taskley.TaskleyWidgetProvider',
      );
    } catch (e) {
      debugPrint('Home widget refresh skipped: $e');
    }
  }
}
