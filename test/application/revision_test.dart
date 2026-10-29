import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:studyflow/application/revision_service.dart';
import 'package:studyflow/core/time/clock.dart';
import 'package:studyflow/data/database/app_database.dart';
import 'package:studyflow/data/database/tables.dart';
import 'package:studyflow/data/repositories/goal_repository.dart';
import 'package:studyflow/data/repositories/session_repository.dart';
import 'package:studyflow/data/repositories/settings_repository.dart';
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
  late AppDatabase database;
  late _FixedClock clock;
  late TopicRepository topicRepository;
  late RevisionService service;
  late String topicId;

  setUp(() async {
    database = AppDatabase.forTesting(NativeDatabase.memory());
    clock = _FixedClock(DateTime(2026, 10, 29, 10));
    topicRepository = TopicRepository(database);
    final goal = await GoalRepository(database).insert(title: 'Learn Spanish');
    final subject = await SubjectRepository(
      database,
    ).insert(goalId: goal.id, title: 'Grammar');
    final topic = await topicRepository.insert(
      subjectId: subject.id,
      title: 'Verb tenses',
      status: TopicStatus.learned,
    );
    topicId = topic.id;
    service = RevisionService(
      topicRepository: topicRepository,
      taskRepository: TaskRepository(database, clock: clock),
      settingsRepository: SettingsRepository(database),
      clock: clock,
    );
  });

  tearDown(() => database.close());

  Future<List<Task>> loadTasks() {
    return (database.select(database.tasks)
          ..where((t) => t.topicId.equals(topicId))
          ..orderBy([(t) => OrderingTerm.asc(t.revisionStage)]))
        .get();
  }

  test('standard preset generates four staged revision tasks', () async {
    await service.generateRevisionsForTopic(topicId);

    final tasks = await loadTasks();
    expect(tasks, hasLength(4));
    expect(tasks.map((task) => task.revisionStage), [0, 1, 2, 3]);
    expect(tasks.map((task) => task.notBeforeDate), [
      '2026-10-30',
      '2026-11-01',
      '2026-11-05',
      '2026-11-12',
    ]);
    for (final task in tasks) {
      expect(task.title, 'Revise: Verb tenses');
      expect(task.kind, TaskKind.revision);
      expect(task.priority, 1);
      expect(task.estimateMinutes, 25);
      expect(task.remainingMinutes, 25);
      expect(task.deadlineDate, isNull);
      expect(task.status, TaskStatus.open);
    }

    final topic = await topicRepository.getById(topicId);
    expect(topic!.learnedOn, '2026-10-29');
    expect(topic.revisionCycleStartedOn, '2026-10-29');
  });

  test('generating again does not duplicate revisions', () async {
    await service.generateRevisionsForTopic(topicId);
    await service.generateRevisionsForTopic(topicId);

    final tasks = await loadTasks();
    expect(tasks, hasLength(4));
    expect(tasks.map((task) => task.revisionStage), [0, 1, 2, 3]);
  });

  test('completing a task deletes its future scheduled sessions', () async {
    final taskRepository = TaskRepository(database, clock: clock);
    final sessions = SessionRepository(database);
    final task = await taskRepository.insert(
      topicId: topicId,
      title: 'Conjugate verbs',
      estimateMinutes: 60,
    );
    final future = await sessions.insert(
      taskId: task.id,
      sessionDate: clock.today.addDays(1).toString(),
      startMinute: 18 * 60,
      plannedMinutes: 50,
    );
    final laterToday = await sessions.insert(
      taskId: task.id,
      sessionDate: clock.today.toString(),
      startMinute: 18 * 60,
      plannedMinutes: 50,
    );
    final history = await sessions.insert(
      taskId: task.id,
      sessionDate: clock.today.addDays(-1).toString(),
      startMinute: 18 * 60,
      plannedMinutes: 50,
      actualMinutes: 50,
      status: SessionStatus.completed,
      completedAtUtc: clock.now.millisecondsSinceEpoch,
    );

    await taskRepository.update(
      task.copyWith(
        status: TaskStatus.completed,
        remainingMinutes: 0,
        completedAt: Value(clock.now.millisecondsSinceEpoch),
      ),
    );

    expect(await sessions.getById(future.id), isNull);
    expect(await sessions.getById(laterToday.id), isNull);
    final retained = await sessions.getById(history.id);
    expect(retained!.status, SessionStatus.completed);
  });
}
