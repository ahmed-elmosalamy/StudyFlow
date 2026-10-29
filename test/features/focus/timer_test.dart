import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:studyflow/app/providers.dart';
import 'package:studyflow/core/time/clock.dart';
import 'package:studyflow/data/database/app_database.dart';
import 'package:studyflow/data/database/tables.dart';
import 'package:studyflow/data/repositories/goal_repository.dart';
import 'package:studyflow/data/repositories/session_repository.dart';
import 'package:studyflow/data/repositories/settings_repository.dart';
import 'package:studyflow/data/repositories/subject_repository.dart';
import 'package:studyflow/data/repositories/task_repository.dart';
import 'package:studyflow/data/repositories/topic_repository.dart';
import 'package:studyflow/features/focus/providers/timer_provider.dart';

class _MutableClock extends Clock {
  _MutableClock(this._now);

  DateTime _now;

  @override
  DateTime get now => _now;

  void advance(Duration duration) {
    _now = _now.add(duration);
  }
}

void main() {
  late AppDatabase database;
  late _MutableClock clock;
  late ProviderContainer container;
  late ProviderSubscription<AsyncValue<TimerState>> subscription;
  late String taskId;
  late String sessionId;

  setUp(() async {
    database = AppDatabase.forTesting(NativeDatabase.memory());
    clock = _MutableClock(DateTime(2026, 10, 29, 10));
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
    final session = await SessionRepository(database).insert(
      taskId: taskId,
      sessionDate: '2026-10-29',
      startMinute: 18 * 60,
      plannedMinutes: 50,
    );
    sessionId = session.id;
    container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWith((ref) {
          ref.onDispose(database.close);
          return database;
        }),
        clockProvider.overrideWithValue(clock),
      ],
    );
    subscription = container.listen(
      timerControllerProvider(sessionId),
      (_, _) {},
      fireImmediately: true,
    );
  });

  tearDown(() {
    subscription.close();
    container.dispose();
  });

  Future<TimerController> loadController() async {
    await container.read(timerControllerProvider(sessionId).future);
    return container.read(timerControllerProvider(sessionId).notifier);
  }

  test('start marks the session in progress', () async {
    final controller = await loadController();

    await controller.start();

    final session = await SessionRepository(database).getById(sessionId);
    expect(session!.status, SessionStatus.in_progress);
    expect(session.startedAtUtc, clock.now.millisecondsSinceEpoch);
    expect(session.timerResumedAtUtc, clock.now.millisecondsSinceEpoch);
    expect(session.timerAccumulatedSeconds, 0);

    final state = container.read(timerControllerProvider(sessionId)).value!;
    expect(state.isRunning, isTrue);
    expect(state.elapsedSeconds(clock.now), 0);
  });

  test('pause and resume accumulate elapsed seconds', () async {
    final controller = await loadController();
    await controller.start();

    clock.advance(const Duration(minutes: 5, seconds: 30));
    await controller.pause();

    var session = await SessionRepository(database).getById(sessionId);
    expect(session!.timerAccumulatedSeconds, 330);
    expect(session.timerResumedAtUtc, isNull);
    expect(session.status, SessionStatus.in_progress);

    clock.advance(const Duration(minutes: 10));
    var state = container.read(timerControllerProvider(sessionId)).value!;
    expect(state.elapsedSeconds(clock.now), 330);

    await controller.resume();
    session = await SessionRepository(database).getById(sessionId);
    expect(session!.timerResumedAtUtc, clock.now.millisecondsSinceEpoch);

    clock.advance(const Duration(minutes: 2));
    await controller.pause();
    session = await SessionRepository(database).getById(sessionId);
    expect(session!.timerAccumulatedSeconds, 450);

    state = container.read(timerControllerProvider(sessionId)).value!;
    expect(state.isRunning, isFalse);
    expect(state.accumulatedSeconds, 450);
  });

  test('finish completes the session and reduces task remaining', () async {
    final controller = await loadController();
    await controller.start();
    clock.advance(const Duration(minutes: 30));

    await controller.finish(25);

    final session = await SessionRepository(database).getById(sessionId);
    expect(session!.status, SessionStatus.completed);
    expect(session.actualMinutes, 25);
    expect(session.completedAtUtc, clock.now.millisecondsSinceEpoch);
    expect(session.timerResumedAtUtc, isNull);
    expect(session.timerAccumulatedSeconds, 30 * 60);

    final task = await TaskRepository(database).getById(taskId);
    expect(task!.remainingMinutes, 35);
    expect(task.status, TaskStatus.open);

    final settings = await SettingsRepository(database).getSettings();
    expect(settings.lastPlanAt, clock.now.millisecondsSinceEpoch);
  });

  test(
    'finish completing the remaining work deletes future sessions',
    () async {
      final futureSession = await SessionRepository(database).insert(
        taskId: taskId,
        sessionDate: clock.today.addDays(1).toString(),
        startMinute: 18 * 60,
        plannedMinutes: 50,
      );
      final controller = await loadController();
      await controller.start();
      clock.advance(const Duration(minutes: 10));

      await controller.finish(60);

      final task = await TaskRepository(database).getById(taskId);
      expect(task!.remainingMinutes, 0);
      expect(task.status, TaskStatus.completed);

      final future = await SessionRepository(
        database,
      ).getById(futureSession.id);
      expect(future, isNull);
    },
  );

  test('finish with auto-replan off marks the plan stale', () async {
    final settingsRepository = SettingsRepository(database);
    final settings = await settingsRepository.getSettings();
    await settingsRepository.update(settings.copyWith(autoReplan: 0));

    final controller = await loadController();
    await controller.start();
    clock.advance(const Duration(minutes: 5));

    await controller.finish(10);

    final reloaded = await settingsRepository.getSettings();
    expect(reloaded.planStale, 1);
    expect(reloaded.lastPlanAt, isNull);
  });

  test('discard cancels the session without counting time', () async {
    final controller = await loadController();
    await controller.start();
    clock.advance(const Duration(minutes: 5));

    await controller.discard();

    final session = await SessionRepository(database).getById(sessionId);
    expect(session!.status, SessionStatus.cancelled);
    expect(session.actualMinutes, isNull);
    expect(session.timerResumedAtUtc, isNull);
    expect(session.timerAccumulatedSeconds, 5 * 60);

    final task = await TaskRepository(database).getById(taskId);
    expect(task!.remainingMinutes, 60);

    final settings = await SettingsRepository(database).getSettings();
    expect(settings.lastPlanAt, isNull);
  });
}
