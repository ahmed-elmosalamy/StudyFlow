import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:studyflow/application/plan_service.dart';
import 'package:studyflow/core/time/clock.dart';
import 'package:studyflow/data/database/app_database.dart';
import 'package:studyflow/data/database/tables.dart';
import 'package:studyflow/data/repositories/availability_repository.dart';
import 'package:studyflow/data/repositories/goal_repository.dart';
import 'package:studyflow/data/repositories/session_repository.dart';
import 'package:studyflow/data/repositories/settings_repository.dart';
import 'package:studyflow/data/repositories/subject_repository.dart';
import 'package:studyflow/data/repositories/task_repository.dart';
import 'package:studyflow/data/repositories/topic_repository.dart';

class _FixedClock extends Clock {
  _FixedClock(this._now);

  final DateTime _now;

  @override
  DateTime get now => _now;
}

void main() {
  late AppDatabase database;
  late _FixedClock clock;
  late PlanService service;
  late String taskId;

  setUp(() async {
    database = AppDatabase.forTesting(NativeDatabase.memory());
    clock = _FixedClock(DateTime(2026, 10, 29, 10));
    final goal = await GoalRepository(database).insert(title: 'Learn Spanish');
    final subject = await SubjectRepository(
      database,
    ).insert(goalId: goal.id, title: 'Grammar');
    final topic = await TopicRepository(
      database,
    ).insert(subjectId: subject.id, title: 'Verb tenses');
    final task = await TaskRepository(
      database,
    ).insert(topicId: topic.id, title: 'Conjugate verbs', estimateMinutes: 60);
    taskId = task.id;
    await AvailabilityRepository(database).insert(
      weekday: clock.today.weekday,
      startMinute: 18 * 60,
      endMinute: 21 * 60,
    );
    service = PlanService(
      database: database,
      taskRepository: TaskRepository(database),
      sessionRepository: SessionRepository(database),
      settingsRepository: SettingsRepository(database),
      availabilityRepository: AvailabilityRepository(database),
      clock: clock,
    );
  });

  tearDown(() => database.close());

  test('persists the generated plan as scheduled sessions', () async {
    final result = await service.replan();

    expect(result.issues, isEmpty);
    expect(result.sessions, hasLength(2));

    final sessions = await database.select(database.studySessions).get();
    expect(sessions, hasLength(2));
    sessions.sort((a, b) => a.startMinute.compareTo(b.startMinute));
    expect(sessions[0].taskId, taskId);
    expect(sessions[0].sessionDate, '2026-10-29');
    expect(sessions[0].startMinute, 18 * 60);
    expect(sessions[0].plannedMinutes, 50);
    expect(sessions[0].status, SessionStatus.scheduled);
    expect(sessions[1].startMinute, 19 * 60);
    expect(sessions[1].plannedMinutes, 10);
    expect(sessions[1].status, SessionStatus.scheduled);

    final settings = await SettingsRepository(database).getSettings();
    expect(settings.lastPlanAt, clock.now.millisecondsSinceEpoch);
    expect(settings.planStale, 0);
  });

  test('replanning replaces future sessions without duplicates', () async {
    await service.replan();
    final firstRows = await database.select(database.studySessions).get();
    expect(firstRows, hasLength(2));
    final firstIds = firstRows.map((row) => row.id).toSet();

    final second = await service.replan();
    expect(second.sessions, hasLength(2));

    final secondRows = await database.select(database.studySessions).get();
    expect(secondRows, hasLength(2));
    expect(
      secondRows.map((row) => row.id).toSet().intersection(firstIds),
      isEmpty,
    );

    final slots =
        secondRows
            .map(
              (row) =>
                  '${row.sessionDate} ${row.startMinute} '
                  '${row.plannedMinutes}',
            )
            .toList()
          ..sort();
    expect(slots, ['2026-10-29 1080 50', '2026-10-29 1140 10']);
  });

  test('retains active and completed sessions across a replan', () async {
    final sessionRepository = SessionRepository(database);
    final today = clock.today.toString();
    final completed = await sessionRepository.insert(
      taskId: taskId,
      sessionDate: today,
      startMinute: 8 * 60,
      plannedMinutes: 30,
      actualMinutes: 25,
      status: SessionStatus.completed,
    );
    final active = await sessionRepository.insert(
      taskId: taskId,
      sessionDate: today,
      startMinute: 9 * 60 + 30,
      plannedMinutes: 50,
    );

    final result = await service.replan();
    expect(result.issues, isEmpty);

    final rows = await database.select(database.studySessions).get();
    final byId = {for (final row in rows) row.id: row};
    expect(byId[completed.id]?.status, SessionStatus.completed);
    expect(byId[active.id]?.status, SessionStatus.scheduled);

    final scheduled = rows
        .where((row) => row.status == SessionStatus.scheduled)
        .toList();
    expect(scheduled, hasLength(2));
    final planned = scheduled.where((row) => row.id != active.id).toList();
    expect(planned, hasLength(1));
    expect(planned.single.startMinute, 18 * 60);
    expect(planned.single.plannedMinutes, 10);
  });
}
