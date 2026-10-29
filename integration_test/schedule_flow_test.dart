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
import 'package:studyflow/data/repositories/availability_repository.dart';
import 'package:studyflow/data/repositories/goal_repository.dart';
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

  testWidgets('generates and regenerates the schedule', (tester) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    final today = DateTime.now();
    final clock = _FixedClock(DateTime(today.year, today.month, today.day, 10));

    final goal = await GoalRepository(database).insert(title: 'Learn Spanish');
    final subject = await SubjectRepository(
      database,
    ).insert(goalId: goal.id, title: 'Grammar');
    final topic = await TopicRepository(
      database,
    ).insert(subjectId: subject.id, title: 'Verb tenses');
    await TaskRepository(
      database,
    ).insert(topicId: topic.id, title: 'Conjugate verbs', estimateMinutes: 90);
    await AvailabilityRepository(database).insert(
      weekday: clock.today.weekday,
      startMinute: 18 * 60,
      endMinute: 21 * 60,
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
        matching: find.text('Schedule'),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('No plan generated yet. Tap Generate Plan.'),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('generate-plan-button')));
    await _pumpUntilFound(tester, find.text('19:00 - 19:40 | 40 min'));

    expect(find.text('18:00 - 18:50 | 50 min'), findsOneWidget);
    expect(find.text('19:00 - 19:40 | 40 min'), findsOneWidget);
    expect(find.byType(Card), findsNWidgets(2));

    final firstIds = await _scheduledIds(database);
    expect(firstIds, hasLength(2));

    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('generate-plan-button')));
    await tester.pumpAndSettle();

    final deadline = DateTime.now().add(const Duration(seconds: 15));
    var secondIds = await _scheduledIds(database);
    while (secondIds.intersection(firstIds).isNotEmpty) {
      if (DateTime.now().isAfter(deadline)) {
        fail('The second plan run did not replace the scheduled sessions.');
      }
      await tester.pump(const Duration(milliseconds: 100));
      secondIds = await _scheduledIds(database);
    }
    expect(secondIds, hasLength(2));

    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('18:00 - 18:50 | 50 min'), findsOneWidget);
    expect(find.text('19:00 - 19:40 | 40 min'), findsOneWidget);
    expect(find.byType(Card), findsNWidgets(2));

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 100));
  });
}

Future<void> _pumpUntilFound(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 15),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (finder.evaluate().isEmpty) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Timed out waiting for $finder.');
    }
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<Set<String>> _scheduledIds(AppDatabase database) async {
  final rows = await (database.select(
    database.studySessions,
  )..where((t) => t.status.equalsValue(SessionStatus.scheduled))).get();
  return rows.map((row) => row.id).toSet();
}
