import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskley/app.dart';
import 'package:taskley/core/db/database.dart';
import 'package:taskley/core/providers.dart';

import 'app_flow_test.dart' show FakeHomeWidgetService, FakeNotificationService;

/// Task rows use a checkbox where other screens use a 24dp icon. A checkbox
/// carries its own tap padding and centres its circle inside it, which used to
/// push task titles 24dp right of every other row's title.
void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() async => db.close());

  testWidgets('task rows share the leading and title columns of other rows',
      (tester) async {
    await tester.runAsync(() async {
      final listId = await db.createList('Groceries');
      await db.insertTask(
          TasksCompanion.insert(title: 'Milk', listId: Value(listId)));
    });

    await tester.pumpWidget(ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        notificationServiceProvider.overrideWithValue(FakeNotificationService()),
        homeWidgetServiceProvider.overrideWithValue(FakeHomeWidgetService()),
      ],
      child: const TaskleyApp(),
    ));
    await tester.pumpAndSettle();

    final iconLeft = tester.getTopLeft(find.byIcon(Icons.list_alt)).dx;
    final titleLeft = tester.getTopLeft(find.text('Groceries')).dx;

    await tester.tap(find.text('Groceries'));
    await tester.pumpAndSettle();

    // The checkbox's circle is centred in its larger box, so compare the
    // circle's edge rather than the box's.
    final box = tester.getRect(find.byType(Checkbox));
    const checkboxCircle = 18.0;
    final circleLeft = box.left + (box.width - checkboxCircle) / 2;

    expect(circleLeft, iconLeft);
    expect(tester.getTopLeft(find.text('Milk')).dx, titleLeft);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });
}
