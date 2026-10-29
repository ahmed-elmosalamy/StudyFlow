import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:studyflow/app/app.dart';
import 'package:studyflow/app/providers.dart';
import 'package:studyflow/data/database/app_database.dart';

void main() {
  testWidgets('app shell navigates across tabs and settings', (tester) async {
    await tester.pumpWidget(_buildApp());
    await tester.pump();

    expect(
      find.text('Today screen - arrives in a later milestone.'),
      findsOneWidget,
    );

    await _tapTab(tester, 'Goals');
    await tester.pumpAndSettle();
    expect(
      find.text('No goals yet. Create one to get started!'),
      findsOneWidget,
    );

    await _tapTab(tester, 'Schedule');
    expect(
      find.text('Schedule screen - arrives in a later milestone.'),
      findsOneWidget,
    );

    await _tapTab(tester, 'Progress');
    expect(
      find.text('Progress screen - arrives in a later milestone.'),
      findsOneWidget,
    );

    await tester.tap(find.byTooltip('Settings'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(
      find.text('Settings screen - arrives in a later milestone.'),
      findsOneWidget,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 100));
  });
}

Widget _buildApp() {
  return ProviderScope(
    overrides: [
      databaseProvider.overrideWith((ref) {
        final database = AppDatabase.forTesting(NativeDatabase.memory());
        ref.onDispose(database.close);
        return database;
      }),
    ],
    child: const StudyFlowApp(),
  );
}

Future<void> _tapTab(WidgetTester tester, String label) async {
  await tester.tap(
    find.descendant(of: find.byType(NavigationBar), matching: find.text(label)),
  );
  await tester.pump();
}
