import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../core/scheduling/scheduling_models.dart' as engine;
import '../core/scheduling/study_scheduler.dart';
import '../core/time/clock.dart';
import '../core/time/local_date.dart';
import '../data/database/app_database.dart';
import '../data/database/tables.dart';
import '../data/repositories/availability_repository.dart';
import '../data/repositories/session_repository.dart';
import '../data/repositories/settings_repository.dart';
import '../data/repositories/task_repository.dart';

class PlanService {
  PlanService({
    required this.database,
    required this.taskRepository,
    required this.sessionRepository,
    required this.settingsRepository,
    required this.availabilityRepository,
    required this.clock,
  });

  final AppDatabase database;
  final TaskRepository taskRepository;
  final SessionRepository sessionRepository;
  final SettingsRepository settingsRepository;
  final AvailabilityRepository availabilityRepository;
  final Clock clock;

  static const _uuid = Uuid();

  Future<engine.PlanResult> replan() async {
    final today = clock.today;
    final nowMinute = clock.nowMinuteOfDay;
    final settings = await settingsRepository.getSettings();
    final windows = await availabilityRepository.getAll();
    final tasks = await taskRepository.getPlannableTasks();
    final candidates = await sessionRepository.getPlanningCandidates(
      today: today.toString(),
    );

    final input = engine.SchedulingInput(
      today: today,
      nowMinuteOfDay: nowMinute,
      horizonDays: settings.horizonDays,
      settings: engine.SchedulingSettings(
        dailyLimitMinutes: settings.dailyLimitMinutes,
        blockLengthMinutes: settings.blockLengthMinutes,
        minSessionMinutes: settings.minSessionMinutes,
        breakMinutes: settings.breakMinutes,
      ),
      availability: [
        for (final window in windows)
          engine.AvailabilityWindow(
            weekday: window.weekday,
            startMinute: window.startMinute,
            endMinute: window.endMinute,
          ),
      ],
      tasks: [for (final task in tasks) _toEngineTask(task)],
      lockedSessions: _toLockedSessions(
        candidates,
        today: today,
        nowMinute: nowMinute,
      ),
    );

    final result = generatePlan(input);
    final nowMillis = clock.now.millisecondsSinceEpoch;

    await database.transaction(() async {
      await _deleteFutureScheduledSessions(today: today, nowMinute: nowMinute);
      await _insertPlannedSessions(result.sessions, nowMillis: nowMillis);
      await (database.update(
        database.appSettings,
      )..where((t) => t.id.equals(1))).write(
        AppSettingsCompanion(
          lastPlanAt: Value(nowMillis),
          planStale: const Value(0),
          updatedAt: Value(nowMillis),
        ),
      );
    });

    return result;
  }

  engine.EngineTask _toEngineTask(Task task) {
    return engine.EngineTask(
      id: task.id,
      kind: task.kind == TaskKind.revision
          ? engine.TaskKind.revision
          : engine.TaskKind.study,
      priority: _priorityFor(task.priority),
      remainingMinutes: task.remainingMinutes,
      deadline: _parseDate(task.deadlineDate),
      notBefore: _parseDate(task.notBeforeDate),
      createdAt: task.createdAt,
    );
  }

  engine.TaskPriority _priorityFor(int priority) {
    if (priority <= 0) {
      return engine.TaskPriority.low;
    }
    if (priority >= 2) {
      return engine.TaskPriority.high;
    }
    return engine.TaskPriority.normal;
  }

  LocalDate? _parseDate(String? value) {
    return value == null ? null : LocalDate.parse(value);
  }

  List<engine.LockedSession> _toLockedSessions(
    List<StudySession> sessions, {
    required LocalDate today,
    required int nowMinute,
  }) {
    final locked = <engine.LockedSession>[];
    for (final session in sessions) {
      final date = LocalDate.parse(session.sessionDate);
      if (session.status == SessionStatus.completed) {
        if (date.isBefore(today)) {
          continue;
        }
        locked.add(
          engine.LockedSession(
            taskId: session.taskId,
            date: date,
            startMinute: session.startMinute,
            plannedMinutes: session.plannedMinutes,
            status: engine.SessionStatus.completed,
            actualMinutes: session.actualMinutes,
          ),
        );
        continue;
      }
      if (session.status == SessionStatus.in_progress) {
        locked.add(
          engine.LockedSession(
            taskId: session.taskId,
            date: date,
            startMinute: session.startMinute,
            plannedMinutes: session.plannedMinutes,
            status: engine.SessionStatus.inProgress,
            elapsedMinutes: _elapsedMinutes(session),
          ),
        );
        continue;
      }
      final endMinute = session.startMinute + session.plannedMinutes;
      if (!date.isSameDay(today) ||
          session.startMinute > nowMinute ||
          nowMinute >= endMinute) {
        continue;
      }
      locked.add(
        engine.LockedSession(
          taskId: session.taskId,
          date: date,
          startMinute: session.startMinute,
          plannedMinutes: session.plannedMinutes,
          status: engine.SessionStatus.activeScheduledToday,
        ),
      );
    }
    return locked;
  }

  int _elapsedMinutes(StudySession session) {
    var seconds = session.timerAccumulatedSeconds;
    final resumedAt = session.timerResumedAtUtc;
    if (resumedAt != null) {
      final runningMillis = clock.now.millisecondsSinceEpoch - resumedAt;
      if (runningMillis > 0) {
        seconds += runningMillis ~/ 1000;
      }
    }
    return seconds ~/ 60;
  }

  Future<void> _deleteFutureScheduledSessions({
    required LocalDate today,
    required int nowMinute,
  }) {
    final todayString = today.toString();
    return (database.delete(database.studySessions)..where(
          (t) =>
              t.status.equalsValue(SessionStatus.scheduled) &
              (t.sessionDate.isBiggerThanValue(todayString) |
                  (t.sessionDate.equals(todayString) &
                      t.startMinute.isBiggerThanValue(nowMinute))),
        ))
        .go();
  }

  Future<void> _insertPlannedSessions(
    List<engine.PlannedSession> sessions, {
    required int nowMillis,
  }) async {
    if (sessions.isEmpty) {
      return;
    }
    await database.batch((batch) {
      batch.insertAll(database.studySessions, [
        for (final session in sessions)
          StudySessionsCompanion.insert(
            id: _uuid.v4(),
            taskId: session.taskId,
            sessionDate: session.date.toString(),
            startMinute: session.startMinute,
            plannedMinutes: session.plannedMinutes,
            status: SessionStatus.scheduled,
            createdAt: nowMillis,
            updatedAt: nowMillis,
          ),
      ]);
    });
  }
}
