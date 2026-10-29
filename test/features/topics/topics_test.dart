import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:studyflow/app/app.dart';
import 'package:studyflow/app/providers.dart';
import 'package:studyflow/data/database/app_database.dart';
import 'package:studyflow/data/repositories/goal_repository.dart';
import 'package:studyflow/data/repositories/subject_repository.dart';

void main() {
  testWidgets('creates a topic from the subject detail screen', (tester) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    final goal = await GoalRepository(database).insert(title: 'Learn Spanish');
    await SubjectRepository(database).insert(goalId: goal.id, title: 'Grammar');

    await tester.pumpWidget(_buildApp(database));
    await _openGoals(tester);

    await tester.tap(find.text('Learn Spanish'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Grammar'));
    await tester.pumpAndSettle();
    expect(find.text('No topics yet. Add one to get started!'), findsOneWidget);

    await tester.tap(find.byTooltip('New topic'));
    await tester.pumpAndSettle();
    expect(find.text('New topic'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('topic-title-field')),
      'Verb tenses',
    );
    await tester.enterText(
      find.byKey(const ValueKey('topic-notes-field')),
      'Present and past',
    );
    await tester.tap(find.byKey(const ValueKey('topic-status-field')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Learning').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('topic-save-button')));
    await tester.pumpAndSettle();

    expect(find.text('Verb tenses'), findsOneWidget);
    expect(find.text('Present and past'), findsOneWidget);
    expect(find.text('Learning'), findsOneWidget);

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
