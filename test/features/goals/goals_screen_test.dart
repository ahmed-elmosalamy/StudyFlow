import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:studyflow/app/app.dart';
import 'package:studyflow/app/providers.dart';
import 'package:studyflow/data/database/app_database.dart';

void main() {
  testWidgets('shows the empty state when no goals exist', (tester) async {
    await tester.pumpWidget(_buildApp());
    await _openGoals(tester);

    expect(
      find.text('No goals yet. Create one to get started!'),
      findsOneWidget,
    );

    await _disposeApp(tester);
  });

  testWidgets('creating a goal adds it to the list', (tester) async {
    await tester.pumpWidget(_buildApp());
    await _openGoals(tester);

    await tester.tap(find.byTooltip('New goal'));
    await tester.pumpAndSettle();
    expect(find.text('New goal'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('goal-title-field')),
      'Learn Spanish',
    );
    await tester.enterText(
      find.byKey(const ValueKey('goal-description-field')),
      'Finish the A2 course',
    );
    await tester.tap(find.byKey(const ValueKey('goal-color-2')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('goal-save-button')));
    await tester.pumpAndSettle();

    expect(find.text('Learn Spanish'), findsOneWidget);
    expect(find.text('Finish the A2 course'), findsOneWidget);
    expect(find.text('No goals yet. Create one to get started!'), findsNothing);

    await _disposeApp(tester);
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

Future<void> _openGoals(WidgetTester tester) async {
  await tester.pump();
  await tester.tap(
    find.descendant(
      of: find.byType(NavigationBar),
      matching: find.text('Goals'),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _disposeApp(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 100));
}
