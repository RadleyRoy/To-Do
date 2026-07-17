import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../db/database.dart';
import '../utils/date_utils.dart';
import '../widget/home_widget_service.dart';

/// Notification action ids.
const kActionDone = 'done';
const kActionSnooze = 'snooze';

/// Handles the "Done" notification button while the app may not be running.
/// Runs in its own isolate: opens its own database connection, completes the
/// task, schedules the next reminder for recurring tasks, refreshes the
/// home-screen widget.
@pragma('vm:entry-point')
Future<void> notificationBackgroundHandler(NotificationResponse response) async {
  if (response.actionId != kActionDone) return;
  final taskId = int.tryParse(response.payload ?? '');
  if (taskId == null) return;

  final db = AppDatabase.open();
  try {
    final task = await db.getTask(taskId);
    if (task == null) return;
    final service = NotificationService();
    await service.init();
    final updated = await db.completeTask(task);
    await service.syncTaskReminder(updated);
    await HomeWidgetService().refresh(db);
  } catch (e) {
    debugPrint('Notification action failed: $e');
  } finally {
    await db.close();
  }
}

/// Schedules exact-alarm reminders for tasks with a due date and alarm
/// enabled. Notification id == task id, so a task always has at most one
/// pending reminder. The reminder fires at `dueAt - reminderOffset`, or at
/// `snoozedUntil` when the user snoozed it.
class NotificationService {
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  /// Set by the app shell; called when the user taps a reminder (actionId
  /// null) or its Snooze button (actionId == [kActionSnooze]).
  void Function(int taskId, String? actionId)? onTapTask;

  /// Tap that launched the app, if any. Consumed once by the shell.
  (int taskId, String? actionId)? _launchTap;

  Future<void> init() async {
    tz_data.initializeTimeZones();
    try {
      final info = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(info.identifier));
    } catch (e) {
      // Fall back to the bundled default (UTC): reminders still fire, at
      // worst offset by the tz difference until next app start.
      debugPrint('Could not resolve local timezone: $e');
    }

    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
      onDidReceiveNotificationResponse: (response) {
        final id = int.tryParse(response.payload ?? '');
        if (id != null) onTapTask?.call(id, response.actionId);
      },
      onDidReceiveBackgroundNotificationResponse: notificationBackgroundHandler,
    );

    final launch = await _plugin.getNotificationAppLaunchDetails();
    if (launch?.didNotificationLaunchApp ?? false) {
      final response = launch!.notificationResponse;
      final id = int.tryParse(response?.payload ?? '');
      if (id != null) _launchTap = (id, response?.actionId);
    }
  }

  (int taskId, String? actionId)? takeLaunchTap() {
    final tap = _launchTap;
    _launchTap = null;
    return tap;
  }

  AndroidFlutterLocalNotificationsPlugin? get _android =>
      _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();

  Future<bool> requestPermissions() async {
    final android = _android;
    if (android == null) return true;
    final granted = await android.requestNotificationsPermission() ?? false;
    // USE_EXACT_ALARM is granted at install time for alarm/reminder apps; if
    // it ever isn't (e.g. manifest changes), fall back to asking.
    if (!(await android.canScheduleExactNotifications() ?? true)) {
      await android.requestExactAlarmsPermission();
    }
    return granted;
  }

  Future<bool> notificationsEnabled() async =>
      await _android?.areNotificationsEnabled() ?? true;

  Future<bool> exactAlarmsAllowed() async =>
      await _android?.canScheduleExactNotifications() ?? true;

  /// When this task's reminder should ring, or null for "no reminder".
  @visibleForTesting
  static DateTime? reminderTime(Task task, {DateTime? now}) {
    final ref = now ?? DateTime.now();
    if (!task.hasAlarm || task.isDone || task.dueAt == null) return null;
    final snoozed = task.snoozedUntil;
    if (snoozed != null && snoozed.isAfter(ref)) return snoozed;
    final offset = Duration(minutes: task.reminderOffsetMinutes ?? 0);
    final at = task.dueAt!.subtract(offset);
    return at.isAfter(ref) ? at : null;
  }

  /// Schedules or cancels the reminder for [task] to match its current state.
  Future<void> syncTaskReminder(Task task) async {
    final at = reminderTime(task);
    if (at == null) {
      await _plugin.cancel(id: task.id);
      return;
    }
    try {
      await _plugin.zonedSchedule(
        id: task.id,
        title: task.title,
        body: _body(task),
        scheduledDate: tz.TZDateTime.from(at, tz.local),
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            'task_reminders',
            'Task reminders',
            channelDescription: 'Alarms for tasks with a due date',
            importance: Importance.max,
            priority: Priority.high,
            category: AndroidNotificationCategory.reminder,
            actions: const [
              AndroidNotificationAction(kActionDone, 'Done',
                  showsUserInterface: false, cancelNotification: true),
              AndroidNotificationAction(kActionSnooze, 'Snooze',
                  showsUserInterface: true, cancelNotification: true),
            ],
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        payload: '${task.id}',
      );
    } catch (e) {
      // Scheduling must never break task edits (e.g. exact alarms revoked).
      debugPrint('Failed to schedule reminder for task ${task.id}: $e');
    }
  }

  String? _body(Task task) {
    final parts = <String>[
      if (task.dueAt != null) 'Due ${formatDueAbsolute(task.dueAt!)}',
      if (task.notes?.trim().isNotEmpty ?? false) task.notes!.trim(),
    ];
    return parts.isEmpty ? null : parts.join('\n');
  }

  Future<void> cancelTaskReminder(int taskId) => _plugin.cancel(id: taskId);

  /// Re-syncs every pending alarm. Run at app start (covers app updates and
  /// missed boot events) and after restoring a backup.
  Future<void> rescheduleAll(AppDatabase db) async {
    await _plugin.cancelAll();
    for (final task in await db.tasksNeedingAlarms()) {
      await syncTaskReminder(task);
    }
  }
}
