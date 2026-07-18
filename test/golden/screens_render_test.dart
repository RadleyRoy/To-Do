@Tags(['golden'])
library;

import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskley/app.dart';
import 'package:taskley/core/db/database.dart';
import 'package:taskley/core/providers.dart';
import 'package:taskley/core/recurrence/recurrence_engine.dart';

import '../widget/app_flow_test.dart'
    show FakeHomeWidgetService, FakeNotificationService;

/// Renders the app's screens to PNGs so the design can actually be looked at:
///
///   flutter test --update-goldens --tags golden
///
/// Excluded from CI (`--exclude-tags golden`) because rendering differs
/// between platforms; these are a design tool, not an assertion.
void main() {
  setUpAll(() async {
    // flutter_test ships a font that draws every glyph as a box; load the
    // real Roboto so the screenshots show actual text. flutter_tester lives at
    // <sdk>/bin/cache/artifacts/engine/<platform>/, so walk up to `artifacts`.
    Directory? fontsDir;
    var dir = File(Platform.resolvedExecutable).parent;
    for (var i = 0; i < 6 && fontsDir == null; i++) {
      final candidate = Directory('${dir.path}/material_fonts');
      if (candidate.existsSync()) fontsDir = candidate;
      dir = dir.parent;
    }
    if (fontsDir == null) {
      fail('material_fonts not found — screenshots would render text as boxes');
    }
    final loader = FontLoader('Roboto');
    for (final weight in ['regular', 'medium', 'bold', 'light']) {
      final file = File('${fontsDir.path}/roboto-$weight.ttf');
      if (file.existsSync()) {
        loader.addFont(Future.value(file.readAsBytesSync().buffer.asByteData()));
      }
    }
    await loader.load();

    // ...and the icon font, so icons aren't blank squares.
    final icons = File('${fontsDir.path}/MaterialIcons-Regular.otf');
    if (icons.existsSync()) {
      await (FontLoader('MaterialIcons')
            ..addFont(Future.value(icons.readAsBytesSync().buffer.asByteData())))
          .load();
    }
  });

  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() async => db.close());

  Future<void> pump(WidgetTester tester, {Brightness? brightness}) async {
    tester.view
      ..physicalSize = const Size(1236, 2745)
      ..devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        notificationServiceProvider.overrideWithValue(FakeNotificationService()),
        homeWidgetServiceProvider.overrideWithValue(FakeHomeWidgetService()),
      ],
      child: MediaQuery(
        data: MediaQueryData(
            platformBrightness: brightness ?? Brightness.dark,
            size: const Size(412, 915)),
        child: const TaskleyApp(),
      ),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> shoot(WidgetTester tester, String name) async {
    await expectLater(
        find.byType(TaskleyApp), matchesGoldenFile('shots/$name.png'));
    // Unmount so drift's stream-close timers fire inside the test.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  }

  /// Radley's actual data: one empty list, nothing due.
  Future<void> seedSparse() async {
    await db.createList('Groceries');
  }

  Future<void> seedFull() async {
    final groceries = await db.createList('Groceries');
    final home = await db.createList('Car & Home');
    await db.createList('Birthdays');
    final now = DateTime.now();
    await db.insertTask(
        TasksCompanion.insert(title: 'Milk', listId: Value(groceries)));
    await db.insertTask(
        TasksCompanion.insert(title: 'Eggs', listId: Value(groceries)));
    final rice = await db.insertTask(
        TasksCompanion.insert(title: 'Rice', listId: Value(groceries)));
    await db.completeTask((await db.getTask(rice))!);
    await db.insertTask(TasksCompanion.insert(
      title: 'Car Service',
      listId: Value(home),
      notes: const Value('Use the good garage'),
      dueAt: Value(DateTime(now.year, now.month, now.day, 10, 0)),
      hasAlarm: const Value(true),
      recurrenceType: const Value(RecurrenceType.afterCompletion),
      intervalCount: const Value(6),
      intervalUnit: const Value(IntervalUnit.month),
    ));
    await db.insertTask(TasksCompanion.insert(
        title: 'Water the plants',
        dueAt: Value(now.subtract(const Duration(days: 1)))));
    await db.insertTask(TasksCompanion.insert(
        title: 'Renew phone plan',
        dueAt: Value(now.add(const Duration(days: 3)))));
  }

  testWidgets('home - sparse (dark)', (tester) async {
    await tester.runAsync(seedSparse);
    await pump(tester);
    await shoot(tester, 'home-sparse-dark');
  });

  testWidgets('home - sparse (light)', (tester) async {
    await tester.runAsync(seedSparse);
    await pump(tester, brightness: Brightness.light);
    await shoot(tester, 'home-sparse-light');
  });

  testWidgets('home - populated (dark)', (tester) async {
    await tester.runAsync(seedFull);
    await pump(tester);
    await shoot(tester, 'home-full-dark');
  });

  testWidgets('list detail (dark)', (tester) async {
    await tester.runAsync(seedFull);
    await pump(tester);
    await tester.tap(find.text('Groceries'));
    await tester.pumpAndSettle();
    await shoot(tester, 'list-detail-dark');
  });

  testWidgets('today view (dark)', (tester) async {
    await tester.runAsync(seedFull);
    await pump(tester);
    await tester.tap(find.text('Today'));
    await tester.pumpAndSettle();
    await shoot(tester, 'today-dark');
  });

  testWidgets('calendar (dark)', (tester) async {
    await tester.runAsync(seedFull);
    await pump(tester);
    await tester.tap(find.text('Calendar'));
    await tester.pumpAndSettle();
    await shoot(tester, 'calendar-dark');
  });

  testWidgets('settings (dark)', (tester) async {
    await tester.runAsync(seedFull);
    await pump(tester);
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    await shoot(tester, 'settings-dark');
  });
}
