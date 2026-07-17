import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/db/database.dart';
import 'core/notifications/notification_service.dart';
import 'core/providers.dart';
import 'core/widget/home_widget_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final db = AppDatabase.open();
  final notifications = NotificationService();
  await notifications.init();
  // Covers app updates and anything the boot receiver missed.
  notifications.rescheduleAll(db);
  HomeWidgetService().refresh(db);

  runApp(ProviderScope(
    overrides: [
      databaseProvider.overrideWithValue(db),
      notificationServiceProvider.overrideWithValue(notifications),
    ],
    child: const TaskleyApp(),
  ));
}
