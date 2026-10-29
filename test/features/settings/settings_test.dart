import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:studyflow/app/app.dart';
import 'package:studyflow/app/providers.dart';
import 'package:studyflow/data/database/app_database.dart';
import 'package:studyflow/data/repositories/settings_repository.dart';

void main() {
  testWidgets('updates a planning limit', (tester) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    await tester.pumpWidget(_buildApp(database));
    await _openSettings(tester);

    await tester.tap(find.text('Planning Limits'));
    await tester.pumpAndSettle();

    final dailyLimitField = find.byKey(const ValueKey('daily-limit-field'));
    expect(dailyLimitField, findsOneWidget);

    await tester.enterText(dailyLimitField, '90');
    await tester.tap(find.byKey(const ValueKey('planning-save-button')));
    await tester.pumpAndSettle();

    expect(find.text('Planning limits saved.'), findsOneWidget);
    final saved = await SettingsRepository(database).getSettings();
    expect(saved.dailyLimitMinutes, 90);
    expect(saved.blockLengthMinutes, 50);
    expect(saved.minSessionMinutes, 15);
    expect(saved.breakMinutes, 10);

    await _disposeApp(tester);
  });

  testWidgets('adds an availability window', (tester) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    await tester.pumpWidget(_buildApp(database));
    await _openSettings(tester);

    await tester.tap(find.text('Availability'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('add-window-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('save-window-button')));
    await tester.pumpAndSettle();

    expect(find.text('18:00 - 21:00'), findsOneWidget);
    final windows = await database.select(database.availabilityWindows).get();
    expect(windows, hasLength(1));
    expect(windows.single.weekday, 1);
    expect(windows.single.startMinute, 1080);
    expect(windows.single.endMinute, 1260);

    await _disposeApp(tester);
  });

  testWidgets('rejects an overlapping availability window', (tester) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    await tester.pumpWidget(_buildApp(database));
    await _openSettings(tester);

    await tester.tap(find.text('Availability'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('add-window-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('save-window-button')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('add-window-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('save-window-button')));
    await tester.pumpAndSettle();

    expect(
      find.text('Availability windows cannot overlap on the same weekday.'),
      findsOneWidget,
    );
    final windows = await database.select(database.availabilityWindows).get();
    expect(windows, hasLength(1));

    await _disposeApp(tester);
  });
}

Widget _buildApp(AppDatabase database) {
  return ProviderScope(
    overrides: [
      databaseProvider.overrideWith((ref) {
        ref.onDispose(database.close);
        return database;
      }),
    ],
    child: const StudyFlowApp(),
  );
}

Future<void> _openSettings(WidgetTester tester) async {
  await tester.pump();
  await tester.tap(find.byTooltip('Settings'));
  await tester.pumpAndSettle();
}

Future<void> _disposeApp(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 100));
}
