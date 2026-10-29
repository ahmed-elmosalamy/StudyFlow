import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../core/validation.dart';
import '../database/app_database.dart';
import '../database/tables.dart';

class TaskRepository {
  TaskRepository(this._db);

  final AppDatabase _db;

  static const _uuid = Uuid();

  Stream<List<Task>> watchAll() {
    return (_db.select(
      _db.tasks,
    )..orderBy([(t) => OrderingTerm.asc(t.createdAt)])).watch();
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
  }

  Future<void> deleteOrArchive(String id) async {
    final task = await getById(id);
    if (task == null) {
      throw NotFoundException('Task $id was not found.');
    }
    try {
      await (_db.delete(_db.tasks)..where((t) => t.id.equals(id))).go();
    } catch (error) {
      if (error.toString().contains('FOREIGN KEY constraint failed')) {
        throw const ConflictException(
          'Task has sessions and cannot be deleted. Archive it instead.',
        );
      }
      rethrow;
    }
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
