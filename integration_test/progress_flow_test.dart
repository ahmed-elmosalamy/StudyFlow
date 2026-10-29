import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:studyflow/app/app.dart';
import 'package:studyflow/app/providers.dart';
import 'package:studyflow/core/time/clock.dart';
import 'package:studyflow/data/database/app_database.dart';
import 'package:studyflow/data/database/tables.dart';
import 'package:studyflow/data/repositories/goal_repository.dart';
import 'package:studyflow/data/repositories/session_repository.dart';
import 'package:studyflow/data/repositories/subject_repository.dart';
import 'package:studyflow/data/repositories/task_repository.dart';
import 'package:studyflow/data/repositories/topic_repository.dart';

class _FixedClock extends Clock {
  _FixedClock(this.value);

  final DateTime value;

  @override
  DateTime get now => value;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('shows weekly totals on the Progress tab', (tester) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    final clock = _FixedClock(DateTime(2026, 10, 29, 10));
    final today = clock.today;
    final yesterday = today.addDays(-1);

    final goal = await GoalRepository(database).insert(title: 'Learn Spanish');
    final subject = await SubjectRepository(
      database,
    ).insert(goalId: goal.id, title: 'Grammar');
    final topic = await TopicRepository(
      database,
    ).insert(subjectId: subject.id, title: 'Verb tenses');
    final task = await TaskRepository(
      database,
    ).insert(topicId: topic.id, title: 'Conjugate verbs', estimateMinutes: 120);

    final sessions = SessionRepository(database);
    await sessions.insert(
      taskId: task.id,
      sessionDate: today.toString(),
      startMinute: 9 * 60,
      plannedMinutes: 45,
      actualMinutes: 45,
      status: SessionStatus.completed,
      completedAtUtc: clock.now.millisecondsSinceEpoch,
    );
    await sessions.insert(
      taskId: task.id,
      sessionDate: yesterday.toString(),
      startMinute: 9 * 60,
      plannedMinutes: 30,
      actualMinutes: 30,
      status: SessionStatus.completed,
      completedAtUtc: clock.now
          .subtract(const Duration(days: 1))
          .millisecondsSinceEpoch,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWith((ref) {
            ref.onDispose(database.close);
            return database;
          }),
          clockProvider.overrideWithValue(clock),
        ],
        child: const StudyFlowApp(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Progress'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Total Study Time'), findsOneWidget);
    expect(find.text('1h 15m'), findsOneWidget);
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('progress-sessions-count')))
          .data,
      '2',
    );
    expect(
      find.byKey(ValueKey('progress-bar-${today.toString()}')),
      findsOneWidget,
    );
    expect(
      find.byKey(ValueKey('progress-bar-${yesterday.toString()}')),
      findsOneWidget,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 100));
  });
}
