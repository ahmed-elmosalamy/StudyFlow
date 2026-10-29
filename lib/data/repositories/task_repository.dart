import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../core/time/clock.dart';
import '../../core/validation.dart';
import '../database/app_database.dart';
import '../database/tables.dart';

class TaskRepository {
  TaskRepository(this._db, {this.clock = const SystemClock()});

  final AppDatabase _db;
  final Clock clock;

  static const _uuid = Uuid();

  Stream<List<Task>> watchAll() {
    return (_db.select(
      _db.tasks,
    )..orderBy([(t) => OrderingTerm.asc(t.createdAt)])).watch();
  }

  Future<List<Task>> getPlannableTasks() async {
    final query =
        _db.select(_db.tasks).join([
            innerJoin(_db.topics, _db.topics.id.equalsExp(_db.tasks.topicId)),
            innerJoin(
              _db.subjects,
              _db.subjects.id.equalsExp(_db.topics.subjectId),
            ),
            innerJoin(_db.goals, _db.goals.id.equalsExp(_db.subjects.goalId)),
          ])
          ..where(
            _db.tasks.status.equalsValue(TaskStatus.open) &
                _db.tasks.remainingMinutes.isBiggerThanValue(0) &
                _db.goals.status.equalsValue(GoalStatus.active) &
                _db.subjects.status.equalsValue(SubjectStatus.active) &
                _db.topics.status.equalsValue(TopicStatus.archived).not(),
          )
          ..orderBy([
            OrderingTerm.asc(_db.tasks.createdAt),
            OrderingTerm.asc(_db.tasks.id),
          ]);
    final rows = await query.get();
    return [for (final row in rows) row.readTable(_db.tasks)];
  }

  Future<Task?> getById(String id) {
    return (_db.select(
      _db.tasks,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
  }

  Future<Task> insert({
    required String topicId,
    required String title,
    String? notes,
    TaskKind kind = TaskKind.study,
    int priority = 1,
    required int estimateMinutes,
    int? remainingMinutes,
    String? deadlineDate,
    String? notBeforeDate,
    int? revisionStage,
    TaskStatus status = TaskStatus.open,
  }) async {
    final remaining = remainingMinutes ?? estimateMinutes;
    final validatedTitle = _validate(
      title: title,
      kind: kind,
      priority: priority,
      estimateMinutes: estimateMinutes,
      remainingMinutes: remaining,
      deadlineDate: deadlineDate,
      notBeforeDate: notBeforeDate,
      revisionStage: revisionStage,
    );
    final now = DateTime.now().millisecondsSinceEpoch;
    final task = Task(
      id: _uuid.v4(),
      topicId: topicId,
      title: validatedTitle,
      notes: notes,
      kind: kind,
      priority: priority,
      estimateMinutes: estimateMinutes,
      remainingMinutes: remaining,
      deadlineDate: deadlineDate,
      notBeforeDate: notBeforeDate,
      revisionStage: revisionStage,
      status: status,
      completedAt: null,
      createdAt: now,
      updatedAt: now,
    );
    await _db.into(_db.tasks).insert(task);
    return task;
  }

  Future<void> update(Task task) async {
    final existing = await getById(task.id);
    if (existing == null) {
      throw NotFoundException('Task ${task.id} was not found.');
    }
    final validatedTitle = _validate(
      title: task.title,
      kind: task.kind,
      priority: task.priority,
      estimateMinutes: task.estimateMinutes,
      remainingMinutes: task.remainingMinutes,
      deadlineDate: task.deadlineDate,
      notBeforeDate: task.notBeforeDate,
      revisionStage: task.revisionStage,
    );
    final updated = task.copyWith(
      title: validatedTitle,
      createdAt: existing.createdAt,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );
    await (_db.update(
      _db.tasks,
    )..where((t) => t.id.equals(task.id))).write(updated.toCompanion(false));
    if (_removesScheduledSessions(task.status)) {
      await _deleteFutureScheduledSessions(task.id);
    }
  }

  Future<void> deleteOrArchive(String id) async {
    final task = await getById(id);
    if (task == null) {
      throw NotFoundException('Task $id was not found.');
    }
    try {
      await _db.transaction(() async {
        await _deleteFutureScheduledSessions(id);
        await (_db.delete(_db.tasks)..where((t) => t.id.equals(id))).go();
      });
    } catch (error) {
      if (error.toString().contains('FOREIGN KEY constraint failed')) {
        throw const ConflictException(
          'Task has sessions and cannot be deleted. Archive it instead.',
        );
      }
      rethrow;
    }
  }

  bool _removesScheduledSessions(TaskStatus status) {
    return status == TaskStatus.completed ||
        status == TaskStatus.cancelled ||
        status == TaskStatus.archived;
  }

  Future<void> _deleteFutureScheduledSessions(String taskId) {
    final today = clock.today.toString();
    final nowMinute = clock.nowMinuteOfDay;
    return (_db.delete(_db.studySessions)..where(
          (t) =>
              t.taskId.equals(taskId) &
              t.status.equalsValue(SessionStatus.scheduled) &
              (t.sessionDate.isBiggerThanValue(today) |
                  (t.sessionDate.equals(today) &
                      t.startMinute.isBiggerThanValue(nowMinute))),
        ))
        .go();
  }

  String _validate({
    required String title,
    required TaskKind kind,
    required int priority,
    required int estimateMinutes,
    required int remainingMinutes,
    String? deadlineDate,
    String? notBeforeDate,
    int? revisionStage,
  }) {
    final validatedTitle = ValidationRules.validateTitle(title);
    ValidationRules.validateEstimateMinutes(estimateMinutes);
    ValidationRules.validatePriority(priority);
    ValidationRules.validateRemainingMinutes(
      remainingMinutes: remainingMinutes,
      estimateMinutes: estimateMinutes,
    );
    ValidationRules.validateDate(deadlineDate, field: 'Deadline');
    ValidationRules.validateDate(notBeforeDate, field: 'Not-before date');
    ValidationRules.validateDateOrder(
      earliestDate: notBeforeDate,
      deadlineDate: deadlineDate,
    );
    if (kind == TaskKind.study && revisionStage != null) {
      throw const ValidationException(
        'Study tasks cannot have a revision stage.',
      );
    }
    if (kind == TaskKind.revision && revisionStage == null) {
      throw const ValidationException(
        'Revision tasks require a revision stage.',
      );
    }
    if (revisionStage != null && revisionStage < 0) {
      throw const ValidationException('Revision stage cannot be negative.');
    }
    return validatedTitle;
  }
}
