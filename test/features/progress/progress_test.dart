import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:studyflow/app/providers.dart';
import 'package:studyflow/core/time/clock.dart';
import 'package:studyflow/data/database/app_database.dart';
import 'package:studyflow/data/database/tables.dart';
import 'package:studyflow/data/repositories/goal_repository.dart';
import 'package:studyflow/data/repositories/session_repository.dart';
import 'package:studyflow/data/repositories/subject_repository.dart';
import 'package:studyflow/data/repositories/task_repository.dart';
import 'package:studyflow/data/repositories/topic_repository.dart';
import 'package:studyflow/presentation/progress/progress_screen.dart';

class _FixedClock extends Clock {
  _FixedClock(this.value);

  final DateTime value;

  @override
  DateTime get now => value;
}

void main() {
  testWidgets('summarizes this week and ignores last week', (tester) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    final clock = _FixedClock(DateTime(2026, 10, 29, 10));

    final goal = await GoalRepository(database).insert(title: 'Learn Spanish');
    final subject = await SubjectRepository(
      database,
    ).insert(goalId: goal.id, title: 'Grammar');
    final topic = await TopicRepository(
      database,
    ).insert(subjectId: subject.id, title: 'Verb tenses');
    final task = await TaskRepository(
      database,
    ).insert(topicId: topic.id, title: 'Conjugate verbs', estimateMinutes: 240);

    final sessions = SessionRepository(database);
    Future<void> addCompleted(String date, int minutes) {
      return sessions.insert(
        taskId: task.id,
        sessionDate: date,
        startMinute: 9 * 60,
        plannedMinutes: minutes,
        actualMinutes: minutes,
        status: SessionStatus.completed,
        completedAtUtc: DateTime.parse(
          date,
        ).add(const Duration(hours: 10)).millisecondsSinceEpoch,
      );
    }

    await addCompleted('2026-10-26', 45);
    await addCompleted('2026-10-27', 30);
    await addCompleted('2026-10-29', 60);
    await addCompleted('2026-10-23', 100);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWith((ref) {
            ref.onDispose(database.close);
            return database;
          }),
          clockProvider.overrideWithValue(clock),
        ],
        child: const MaterialApp(home: Scaffold(body: ProgressScreen())),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Total Study Time'), findsOneWidget);
    expect(find.text('Sessions Completed'), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('progress-total'))).data,
      '2h 15m',
    );
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('progress-sessions-count')))
          .data,
      '3',
    );

    double barHeight(String date) {
      return tester.getSize(find.byKey(ValueKey('progress-bar-$date'))).height;
    }

    expect(barHeight('2026-10-26'), 90.0);
    expect(barHeight('2026-10-27'), 60.0);
    expect(barHeight('2026-10-28'), 0.0);
    expect(barHeight('2026-10-29'), 120.0);
    expect(find.byKey(const ValueKey('progress-bar-2026-10-23')), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 100));
  });
}
