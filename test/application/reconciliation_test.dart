import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:studyflow/application/plan_service.dart';
import 'package:studyflow/application/reconciliation_service.dart';
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
  late SessionRepository sessionRepository;
  late SettingsRepository settingsRepository;
  late ReconciliationService service;
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
    sessionRepository = SessionRepository(database);
    settingsRepository = SettingsRepository(database);
    final planService = PlanService(
      database: database,
      taskRepository: TaskRepository(database),
      sessionRepository: sessionRepository,
      settingsRepository: settingsRepository,
      availabilityRepository: AvailabilityRepository(database),
      clock: clock,
    );
    service = ReconciliationService(
      sessionRepository: sessionRepository,
      settingsRepository: settingsRepository,
      planService: planService,
      clock: clock,
    );
  });

  tearDown(() => database.close());

  test(
    'marks past scheduled sessions missed and replans automatically',
    () async {
      final past = await sessionRepository.insert(
        taskId: taskId,
        sessionDate: clock.today.addDays(-1).toString(),
        startMinute: 18 * 60,
        plannedMinutes: 50,
      );

      await service.reconcile();

      final updated = await sessionRepository.getById(past.id);
      expect(updated?.status, SessionStatus.missed);

      final rows = await database.select(database.studySessions).get();
      final scheduled = rows
          .where((row) => row.status == SessionStatus.scheduled)
          .toList();
      expect(scheduled, hasLength(2));
      expect(
        scheduled.every((row) => row.sessionDate == clock.today.toString()),
        isTrue,
      );

      final task = await (database.select(
        database.tasks,
      )..where((t) => t.id.equals(taskId))).getSingle();
      expect(task.remainingMinutes, 60);

      final settings = await settingsRepository.getSettings();
      expect(settings.lastPlanAt, clock.now.millisecondsSinceEpoch);
    },
  );

  test('leaves sessions scheduled for later today untouched', () async {
    final later = await sessionRepository.insert(
      taskId: taskId,
      sessionDate: clock.today.toString(),
      startMinute: 18 * 60,
      plannedMinutes: 50,
    );

    await service.reconcile();

    final updated = await sessionRepository.getById(later.id);
    expect(updated?.status, SessionStatus.scheduled);

    final rows = await database.select(database.studySessions).get();
    expect(rows, hasLength(1));

    final settings = await settingsRepository.getSettings();
    expect(settings.lastPlanAt, isNull);
  });

  test('marks a session that ends exactly now as missed', () async {
    final endingNow = await sessionRepository.insert(
      taskId: taskId,
      sessionDate: clock.today.toString(),
      startMinute: 9 * 60,
      plannedMinutes: 60,
    );

    await service.reconcile();

    final updated = await sessionRepository.getById(endingNow.id);
    expect(updated?.status, SessionStatus.missed);

    final scheduled = (await database.select(database.studySessions).get())
        .where((row) => row.status == SessionStatus.scheduled)
        .toList();
    expect(scheduled, hasLength(2));
  });

  test(
    'marks missed sessions but does not replan when auto-replan is off',
    () async {
      final settings = await settingsRepository.getSettings();
      await settingsRepository.update(settings.copyWith(autoReplan: 0));
      final past = await sessionRepository.insert(
        taskId: taskId,
        sessionDate: clock.today.addDays(-1).toString(),
        startMinute: 18 * 60,
        plannedMinutes: 50,
      );

      await service.reconcile();

      final updated = await sessionRepository.getById(past.id);
      expect(updated?.status, SessionStatus.missed);

      final rows = await database.select(database.studySessions).get();
      expect(rows, hasLength(1));

      final reloaded = await settingsRepository.getSettings();
      expect(reloaded.lastPlanAt, isNull);
    },
  );

  test('reconciling again leaves the existing plan unchanged', () async {
    await sessionRepository.insert(
      taskId: taskId,
      sessionDate: clock.today.addDays(-1).toString(),
      startMinute: 18 * 60,
      plannedMinutes: 50,
    );

    await service.reconcile();
    final firstIds = (await database.select(database.studySessions).get())
        .where((row) => row.status == SessionStatus.scheduled)
        .map((row) => row.id)
        .toSet();
    expect(firstIds, hasLength(2));

    await service.reconcile();

    final rows = await database.select(database.studySessions).get();
    final scheduled = rows
        .where((row) => row.status == SessionStatus.scheduled)
        .toList();
    expect(scheduled.map((row) => row.id).toSet(), firstIds);
    expect(
      rows.where((row) => row.status == SessionStatus.missed),
      hasLength(1),
    );
  });
}
