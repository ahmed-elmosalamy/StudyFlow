import 'dart:math' as math;

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../core/validation.dart';
import '../database/app_database.dart';
import '../database/tables.dart';

class SessionRepository {
  SessionRepository(this._db);

  final AppDatabase _db;

  static const _uuid = Uuid();

  Stream<List<StudySession>> watchAll() {
    return (_db.select(_db.studySessions)..orderBy([
          (t) => OrderingTerm.asc(t.sessionDate),
          (t) => OrderingTerm.asc(t.startMinute),
        ]))
        .watch();
  }

  Stream<List<StudySession>> watchScheduledFrom(String fromDate) {
    return (_db.select(_db.studySessions)
          ..where(
            (t) =>
                t.status.equalsValue(SessionStatus.scheduled) &
                t.sessionDate.isBiggerOrEqualValue(fromDate),
          )
          ..orderBy([
            (t) => OrderingTerm.asc(t.sessionDate),
            (t) => OrderingTerm.asc(t.startMinute),
          ]))
        .watch();
  }

  Stream<List<StudySession>> watchTodaySessions(String date) {
    return (_db.select(_db.studySessions)
          ..where(
            (t) =>
                t.sessionDate.equals(date) &
                (t.status.equalsValue(SessionStatus.scheduled) |
                    t.status.equalsValue(SessionStatus.in_progress)),
          )
          ..orderBy([(t) => OrderingTerm.asc(t.startMinute)]))
        .watch();
  }

  Future<List<StudySession>> getInProgress() {
    return (_db.select(
      _db.studySessions,
    )..where((t) => t.status.equalsValue(SessionStatus.in_progress))).get();
  }

  Future<void> markCompleted(
    String id, {
    required int actualMinutes,
    required int completedAtUtc,
    required int timerAccumulatedSeconds,
    required int updatedAt,
  }) async {
    ValidationRules.validateActualMinutes(actualMinutes);
    ValidationRules.validateTimerSeconds(timerAccumulatedSeconds);
    await (_db.update(_db.studySessions)..where((t) => t.id.equals(id))).write(
      StudySessionsCompanion(
        status: const Value(SessionStatus.completed),
        actualMinutes: Value(actualMinutes),
        completedAtUtc: Value(completedAtUtc),
        timerAccumulatedSeconds: Value(timerAccumulatedSeconds),
        timerResumedAtUtc: const Value(null),
        updatedAt: Value(updatedAt),
      ),
    );
  }

  Future<void> cancelFutureScheduledForTask(
    String taskId, {
    required String today,
    required int nowMinute,
    required int updatedAt,
  }) async {
    await (_db.update(_db.studySessions)..where(
          (t) =>
              t.taskId.equals(taskId) &
              t.status.equalsValue(SessionStatus.scheduled) &
              (t.sessionDate.isBiggerThanValue(today) |
                  (t.sessionDate.equals(today) &
                      t.startMinute.isBiggerThanValue(nowMinute))),
        ))
        .write(
          StudySessionsCompanion(
            status: const Value(SessionStatus.cancelled),
            updatedAt: Value(updatedAt),
          ),
        );
  }

  Future<List<StudySession>> getScheduled() {
    return (_db.select(_db.studySessions)
          ..where((t) => t.status.equalsValue(SessionStatus.scheduled))
          ..orderBy([
            (t) => OrderingTerm.asc(t.sessionDate),
            (t) => OrderingTerm.asc(t.startMinute),
          ]))
        .get();
  }

  Future<void> markMissed(
    Iterable<String> ids, {
    required int updatedAt,
  }) async {
    final idList = ids.toList(growable: false);
    if (idList.isEmpty) {
      return;
    }
    await (_db.update(_db.studySessions)..where(
          (t) =>
              t.id.isIn(idList) & t.status.equalsValue(SessionStatus.scheduled),
        ))
        .write(
          StudySessionsCompanion(
            status: const Value(SessionStatus.missed),
            updatedAt: Value(updatedAt),
          ),
        );
  }

  Future<List<StudySession>> getPlanningCandidates({required String today}) {
    return (_db.select(_db.studySessions)
          ..where(
            (t) =>
                t.status.equalsValue(SessionStatus.completed) |
                t.status.equalsValue(SessionStatus.in_progress) |
                (t.status.equalsValue(SessionStatus.scheduled) &
                    t.sessionDate.equals(today)),
          )
          ..orderBy([
            (t) => OrderingTerm.asc(t.sessionDate),
            (t) => OrderingTerm.asc(t.startMinute),
          ]))
        .get();
  }

  Future<StudySession?> getById(String id) {
    return (_db.select(
      _db.studySessions,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
  }

  Future<StudySession> insert({
    required String taskId,
    required String sessionDate,
    required int startMinute,
    required int plannedMinutes,
    int? actualMinutes,
    SessionStatus status = SessionStatus.scheduled,
    int? startedAtUtc,
    int? completedAtUtc,
    int timerAccumulatedSeconds = 0,
    int? timerResumedAtUtc,
    String? note,
  }) async {
    _validate(
      sessionDate: sessionDate,
      startMinute: startMinute,
      plannedMinutes: plannedMinutes,
      actualMinutes: actualMinutes,
      timerAccumulatedSeconds: timerAccumulatedSeconds,
    );
    final task = await _requireTask(taskId);
    if (status == SessionStatus.scheduled && task.status != TaskStatus.open) {
      throw const ValidationException('Only open tasks can be scheduled.');
    }
    await _ensureNoOverlap(
      sessionDate: sessionDate,
      startMinute: startMinute,
      plannedMinutes: plannedMinutes,
      status: status,
    );
    final now = DateTime.now().millisecondsSinceEpoch;
    final session = StudySession(
      id: _uuid.v4(),
      taskId: taskId,
      sessionDate: sessionDate,
      startMinute: startMinute,
      plannedMinutes: plannedMinutes,
      actualMinutes: actualMinutes,
      status: status,
      startedAtUtc: startedAtUtc,
      completedAtUtc: completedAtUtc,
      timerAccumulatedSeconds: timerAccumulatedSeconds,
      timerResumedAtUtc: timerResumedAtUtc,
      note: note,
      createdAt: now,
      updatedAt: now,
    );
    await _db.into(_db.studySessions).insert(session);
    return session;
  }

  Future<void> update(StudySession session) async {
    final existing = await getById(session.id);
    if (existing == null) {
      throw NotFoundException('Session ${session.id} was not found.');
    }
    _validate(
      sessionDate: session.sessionDate,
      startMinute: session.startMinute,
      plannedMinutes: session.plannedMinutes,
      actualMinutes: session.actualMinutes,
      timerAccumulatedSeconds: session.timerAccumulatedSeconds,
    );
    final task = await _requireTask(session.taskId);
    if (session.status == SessionStatus.scheduled &&
        task.status != TaskStatus.open) {
      throw const ValidationException('Only open tasks can be scheduled.');
    }
    await _ensureNoOverlap(
      sessionDate: session.sessionDate,
      startMinute: session.startMinute,
      plannedMinutes: session.plannedMinutes,
      status: session.status,
      excludeId: session.id,
    );
    final updated = session.copyWith(
      createdAt: existing.createdAt,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );
    await (_db.update(
      _db.studySessions,
    )..where((t) => t.id.equals(session.id))).write(updated.toCompanion(false));
  }

  Future<void> deleteOrArchive(String id) async {
    final session = await getById(id);
    if (session == null) {
      throw NotFoundException('Session $id was not found.');
    }
    if (session.status != SessionStatus.scheduled) {
      throw const ConflictException(
        'Only scheduled sessions can be deleted; active, completed, missed, '
        'and cancelled sessions are preserved.',
      );
    }
    await (_db.delete(_db.studySessions)..where((t) => t.id.equals(id))).go();
  }

  void _validate({
    required String sessionDate,
    required int startMinute,
    required int plannedMinutes,
    int? actualMinutes,
    required int timerAccumulatedSeconds,
  }) {
    ValidationRules.validateDate(sessionDate, field: 'Session date');
    ValidationRules.validateSessionTiming(
      startMinute: startMinute,
      plannedMinutes: plannedMinutes,
    );
    ValidationRules.validateActualMinutes(actualMinutes);
    ValidationRules.validateTimerSeconds(timerAccumulatedSeconds);
  }

  Future<Task> _requireTask(String taskId) async {
    final task = await (_db.select(
      _db.tasks,
    )..where((t) => t.id.equals(taskId))).getSingleOrNull();
    if (task == null) {
      throw NotFoundException('Task $taskId was not found.');
    }
    return task;
  }

  Future<void> _ensureNoOverlap({
    required String sessionDate,
    required int startMinute,
    required int plannedMinutes,
    required SessionStatus status,
    String? excludeId,
  }) async {
    if (status == SessionStatus.cancelled) {
      return;
    }
    final sessions = await (_db.select(
      _db.studySessions,
    )..where((t) => t.sessionDate.equals(sessionDate))).get();
    final endMinute = startMinute + plannedMinutes;
    for (final other in sessions) {
      if (other.id == excludeId || other.status == SessionStatus.cancelled) {
        continue;
      }
      final occupiedMinutes = math.max(
        other.plannedMinutes,
        other.actualMinutes ?? 0,
      );
      final otherEndMinute = other.startMinute + occupiedMinutes;
      if (startMinute < otherEndMinute && other.startMinute < endMinute) {
        throw ConflictException(
          'Session overlaps an existing session on $sessionDate.',
        );
      }
    }
  }
}
