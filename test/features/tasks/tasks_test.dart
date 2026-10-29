import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:studyflow/app/app.dart';
import 'package:studyflow/app/providers.dart';
import 'package:studyflow/data/database/app_database.dart';
import 'package:studyflow/data/repositories/goal_repository.dart';
import 'package:studyflow/data/repositories/subject_repository.dart';
import 'package:studyflow/data/repositories/topic_repository.dart';

void main() {
  testWidgets('creates a task from the topic detail screen', (tester) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    final goal = await GoalRepository(database).insert(title: 'Learn Spanish');
    final subject = await SubjectRepository(
      database,
    ).insert(goalId: goal.id, title: 'Grammar');
    await TopicRepository(
      database,
    ).insert(subjectId: subject.id, title: 'Verb tenses');

    await tester.pumpWidget(_buildApp(database));
    await _openGoals(tester);

    await tester.tap(find.text('Learn Spanish'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Grammar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Verb tenses'));
    await tester.pumpAndSettle();

    expect(find.text('No tasks yet. Add one to get started!'), findsOneWidget);

    await tester.tap(find.byTooltip('New task'));
    await tester.pumpAndSettle();
    expect(find.text('New task'), findsOneWidget);
    expect(find.text('Study'), findsOneWidget);
    expect(find.text('Normal'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('task-title-field')),
      'Practice conjugation',
    );
    await tester.tap(find.byKey(const ValueKey('task-save-button')));
    await tester.pumpAndSettle();

    expect(find.text('Practice conjugation'), findsOneWidget);
    expect(find.text('Normal | 30 min left | No deadline'), findsOneWidget);

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
