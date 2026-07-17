import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../db/database.dart';

/// Schedules exact-alarm reminders for tasks with a due date and alarm
/// enabled. Notification id == task id, so a task always has at most one
/// pending reminder.
class NotificationService {
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  /// Set by the app shell; called with the task id when the user taps a
  /// reminder notification.
  void Function(int taskId)? onTapTask;

  /// Task id from the notification that launched the app, if any. Consumed
  /// once by the shell after the first frame.
  int? _launchTaskId;

  static const _channel = AndroidNotificationDetails(
    'task_reminders',
    'Task reminders',
    channelDescription: 'Alarms for tasks with a due date',
    importance: Importance.max,
    priority: Priority.high,
    category: AndroidNotificationCategory.reminder,
  );

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
        if (id != null) onTapTask?.call(id);
      },
    );

    final launch = await _plugin.getNotificationAppLaunchDetails();
    if (launch?.didNotificationLaunchApp ?? false) {
      _launchTaskId =
          int.tryParse(launch!.notificationResponse?.payload ?? '');
    }
  }

  int? takeLaunchTaskId() {
    final id = _launchTaskId;
    _launchTaskId = null;
    return id;
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

  /// Schedules or cancels the reminder for [task] to match its current state.
  Future<void> syncTaskReminder(Task task) async {
    final dueAt = task.dueAt;
    final shouldSchedule = task.hasAlarm &&
        !task.isDone &&
        dueAt != null &&
        dueAt.isAfter(DateTime.now());
    if (!shouldSchedule) {
      await _plugin.cancel(id: task.id);
      return;
    }
    try {
      await _plugin.zonedSchedule(
        id: task.id,
        title: task.title,
        body: _body(task),
        scheduledDate: tz.TZDateTime.from(dueAt, tz.local),
        notificationDetails: const NotificationDetails(android: _channel),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        payload: '${task.id}',
      );
    } catch (e) {
      // Scheduling must never break task edits (e.g. exact alarms revoked).
      debugPrint('Failed to schedule reminder for task ${task.id}: $e');
    }
  }

  String? _body(Task task) {
    final notes = task.notes;
    if (notes != null && notes.trim().isNotEmpty) return notes.trim();
    return null;
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
