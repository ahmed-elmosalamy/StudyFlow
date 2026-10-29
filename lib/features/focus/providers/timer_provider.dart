import 'dart:async';
import 'dart:math' as math;

import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/time/clock.dart';
import '../../../core/validation.dart';
import '../../../data/database/app_database.dart';
import '../../../data/database/tables.dart';
import '../../../data/repositories/session_repository.dart';
import '../../../data/repositories/task_repository.dart';

class TimerState {
  const TimerState({
    required this.sessionId,
    required this.taskTitle,
    required this.plannedMinutes,
    required this.accumulatedSeconds,
    required this.isRunning,
    required this.startedAtUtc,
    this.hasStarted = false,
    this.tick = 0,
  });

  final String sessionId;
  final String taskTitle;
  final int plannedMinutes;
  final int accumulatedSeconds;
  final bool isRunning;
  final int? startedAtUtc;
  final bool hasStarted;
  final int tick;

  int elapsedSeconds(DateTime now) {
    if (!isRunning || startedAtUtc == null) {
      return accumulatedSeconds;
    }
    final delta = now.millisecondsSinceEpoch - startedAtUtc!;
    return delta <= 0 ? accumulatedSeconds : accumulatedSeconds + delta ~/ 1000;
  }

  TimerState copyWith({
    int? accumulatedSeconds,
    bool? isRunning,
    int? startedAtUtc,
    bool? hasStarted,
    int? tick,
  }) {
    return TimerState(
      sessionId: sessionId,
      taskTitle: taskTitle,
      plannedMinutes: plannedMinutes,
      accumulatedSeconds: accumulatedSeconds ?? this.accumulatedSeconds,
      isRunning: isRunning ?? this.isRunning,
      startedAtUtc: startedAtUtc ?? this.startedAtUtc,
      hasStarted: hasStarted ?? this.hasStarted,
      tick: tick ?? this.tick,
    );
  }
}

final timerControllerProvider = AsyncNotifierProvider.autoDispose
    .family<TimerController, TimerState, String>(TimerController.new);

class TimerController extends AsyncNotifier<TimerState> {
  TimerController(this.sessionId);

  final String sessionId;

  Timer? _ticker;
  String _taskTitle = 'Task';
  int _plannedMinutes = 0;

  SessionRepository get _sessions =>
      SessionRepository(ref.read(databaseProvider));

  TaskRepository get _tasks =>
      TaskRepository(ref.read(databaseProvider), clock: _clock);

  Clock get _clock => ref.read(clockProvider);

  @override
  Future<TimerState> build() async {
    ref.onDispose(_stopTicker);
    final database = ref.watch(databaseProvider);
    final session = await SessionRepository(database).getById(sessionId);
    if (session == null) {
      throw NotFoundException('Session $sessionId was not found.');
    }
    final task = await TaskRepository(database).getById(session.taskId);
    _taskTitle = task?.title ?? 'Task';
    _plannedMinutes = session.plannedMinutes;

    final timer = TimerState(
      sessionId: session.id,
      taskTitle: _taskTitle,
      plannedMinutes: session.plannedMinutes,
      accumulatedSeconds: session.timerAccumulatedSeconds,
      isRunning: session.timerResumedAtUtc != null,
      startedAtUtc: session.timerResumedAtUtc,
      hasStarted:
          session.status == SessionStatus.in_progress ||
          session.timerAccumulatedSeconds > 0 ||
          session.timerResumedAtUtc != null,
    );
    if (timer.isRunning) {
      _startTicker();
    }
    return timer;
  }

  Future<void> start() async {
    final session = await _requireSession();
    if (session.sessionDate != _clock.today.toString()) {
      throw const ValidationException("Only today's sessions can be started.");
    }
    if (session.status != SessionStatus.scheduled) {
      throw const ConflictException('Only scheduled sessions can be started.');
    }
    final inProgress = await _sessions.getInProgress();
    if (inProgress.any((other) => other.id != session.id)) {
      throw const ConflictException(
        'Finish or discard the running session before starting another.',
      );
    }

    final now = _clock.now.millisecondsSinceEpoch;
    await _sessions.update(
      session.copyWith(
        status: SessionStatus.in_progress,
        startedAtUtc: Value(now),
        timerAccumulatedSeconds: 0,
        timerResumedAtUtc: Value(now),
      ),
    );

    if (!ref.mounted) {
      return;
    }
    state = AsyncData(
      TimerState(
        sessionId: sessionId,
        taskTitle: _taskTitle,
        plannedMinutes: _plannedMinutes,
        accumulatedSeconds: 0,
        isRunning: true,
        startedAtUtc: now,
        hasStarted: true,
      ),
    );
    _startTicker();
  }

  Future<void> pause() async {
    final session = await _requireSession();
    if (session.status != SessionStatus.in_progress ||
        session.timerResumedAtUtc == null) {
      return;
    }
    final elapsed = _elapsed(session);
    _stopTicker();
    await _sessions.update(
      session.copyWith(
        timerAccumulatedSeconds: elapsed,
        timerResumedAtUtc: const Value(null),
      ),
    );

    if (!ref.mounted) {
      return;
    }
    final current = state.value;
    state = AsyncData(
      TimerState(
        sessionId: sessionId,
        taskTitle: _taskTitle,
        plannedMinutes: _plannedMinutes,
        accumulatedSeconds: elapsed,
        isRunning: false,
        startedAtUtc: null,
        hasStarted: true,
        tick: current?.tick ?? 0,
      ),
    );
  }

  Future<void> resume() async {
    final session = await _requireSession();
    if (session.status != SessionStatus.in_progress) {
      throw const ConflictException('Only a paused session can be resumed.');
    }
    if (session.timerResumedAtUtc != null) {
      return;
    }

    final now = _clock.now.millisecondsSinceEpoch;
    await _sessions.update(session.copyWith(timerResumedAtUtc: Value(now)));

    if (!ref.mounted) {
      return;
    }
    final current = state.value;
    state = AsyncData(
      TimerState(
        sessionId: sessionId,
        taskTitle: _taskTitle,
        plannedMinutes: _plannedMinutes,
        accumulatedSeconds: current?.accumulatedSeconds ?? 0,
        isRunning: true,
        startedAtUtc: now,
        hasStarted: true,
        tick: current?.tick ?? 0,
      ),
    );
    _startTicker();
  }

  Future<void> finish(int actualMinutes) async {
    if (actualMinutes < 1) {
      throw const ValidationException('Actual minutes must be at least 1.');
    }
    final session = await _requireSession();
    if (session.status != SessionStatus.scheduled &&
        session.status != SessionStatus.in_progress) {
      throw const ConflictException('Only an active session can be finished.');
    }
    final task = await _tasks.getById(session.taskId);
    if (task == null) {
      throw NotFoundException('Task ${session.taskId} was not found.');
    }

    final now = _clock.now;
    final nowMillis = now.millisecondsSinceEpoch;
    final elapsed = _elapsed(session);
    final remaining = math.max(0, task.remainingMinutes - actualMinutes);
    final database = ref.read(databaseProvider);

    await database.transaction(() async {
      await _sessions.markCompleted(
        session.id,
        actualMinutes: actualMinutes,
        completedAtUtc: nowMillis,
        timerAccumulatedSeconds: elapsed,
        updatedAt: nowMillis,
      );
      await _tasks.update(
        task.copyWith(
          remainingMinutes: remaining,
          status: remaining == 0 ? TaskStatus.completed : null,
          completedAt: remaining == 0 ? Value(nowMillis) : const Value.absent(),
        ),
      );
    });
    _stopTicker();

    await ref.read(planServiceProvider).replanIfAutoEnabled();

    if (!ref.mounted) {
      return;
    }
    state = AsyncData(
      TimerState(
        sessionId: sessionId,
        taskTitle: _taskTitle,
        plannedMinutes: _plannedMinutes,
        accumulatedSeconds: elapsed,
        isRunning: false,
        startedAtUtc: null,
        hasStarted: true,
        tick: state.value?.tick ?? 0,
      ),
    );
  }

  Future<void> discard() async {
    final session = await _requireSession();
    if (session.status != SessionStatus.scheduled &&
        session.status != SessionStatus.in_progress) {
      throw const ConflictException('Only an active session can be discarded.');
    }
    final elapsed = _elapsed(session);
    _stopTicker();
    await _sessions.update(
      session.copyWith(
        status: SessionStatus.cancelled,
        timerAccumulatedSeconds: elapsed,
        timerResumedAtUtc: const Value(null),
      ),
    );

    if (!ref.mounted) {
      return;
    }
    state = AsyncData(
      TimerState(
        sessionId: sessionId,
        taskTitle: _taskTitle,
        plannedMinutes: _plannedMinutes,
        accumulatedSeconds: elapsed,
        isRunning: false,
        startedAtUtc: null,
        hasStarted: true,
        tick: state.value?.tick ?? 0,
      ),
    );
  }

  Future<StudySession> _requireSession() async {
    final session = await _sessions.getById(sessionId);
    if (session == null) {
      throw NotFoundException('Session $sessionId was not found.');
    }
    return session;
  }

  int _elapsed(StudySession session) {
    return state.value?.elapsedSeconds(_clock.now) ??
        _elapsedFromStored(session);
  }

  int _elapsedFromStored(StudySession session) {
    final base = session.timerAccumulatedSeconds;
    final resumedAt = session.timerResumedAtUtc;
    if (resumedAt == null) {
      return base;
    }
    final delta = _clock.now.millisecondsSinceEpoch - resumedAt;
    return delta <= 0 ? base : base + delta ~/ 1000;
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!ref.mounted) {
        return;
      }
      final current = state.value;
      if (current == null || !current.isRunning) {
        return;
      }
      state = AsyncData(current.copyWith(tick: current.tick + 1));
    });
  }

  void _stopTicker() {
    _ticker?.cancel();
    _ticker = null;
  }
}
