import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:studyflow/app/app.dart';
import 'package:studyflow/app/providers.dart';
import 'package:studyflow/data/database/app_database.dart';
import 'package:studyflow/data/repositories/goal_repository.dart';

void main() {
  testWidgets('creates a subject from the goal detail screen', (tester) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    await GoalRepository(database).insert(title: 'Learn Spanish');

    await tester.pumpWidget(_buildApp(database));
    await _openGoals(tester);

    await tester.tap(find.text('Learn Spanish'));
    await tester.pumpAndSettle();
    expect(
      find.text('No subjects yet. Add one to get started!'),
      findsOneWidget,
    );

    await tester.tap(find.byTooltip('New subject'));
    await tester.pumpAndSettle();
    expect(find.text('New subject'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('subject-title-field')),
      'Grammar',
    );
    await tester.enterText(
      find.byKey(const ValueKey('subject-notes-field')),
      'Verb tenses',
    );
    await tester.tap(find.byKey(const ValueKey('subject-save-button')));
    await tester.pumpAndSettle();

    expect(find.text('Grammar'), findsOneWidget);
    expect(find.text('Verb tenses'), findsOneWidget);

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
