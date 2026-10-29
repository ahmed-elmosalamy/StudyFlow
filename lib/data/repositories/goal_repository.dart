import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../core/validation.dart';
import '../database/app_database.dart';
import '../database/tables.dart';

class GoalRepository {
  GoalRepository(this._db);

  final AppDatabase _db;

  static const _uuid = Uuid();

  Stream<List<Goal>> watchAll() {
    return (_db.select(
      _db.goals,
    )..orderBy([(t) => OrderingTerm.asc(t.createdAt)])).watch();
  }

  Future<Goal?> getById(String id) {
    return (_db.select(
      _db.goals,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
  }

  Future<Goal> insert({
    required String title,
    String? description,
    String? targetDate,
    int colorIndex = 0,
    GoalStatus status = GoalStatus.active,
  }) async {
    final validatedTitle = ValidationRules.validateTitle(title);
    ValidationRules.validateDate(targetDate, field: 'Target date');
    final now = DateTime.now().millisecondsSinceEpoch;
    final goal = Goal(
      id: _uuid.v4(),
      title: validatedTitle,
      description: description,
      targetDate: targetDate,
      colorIndex: colorIndex,
      status: status,
      createdAt: now,
      updatedAt: now,
    );
    await _db.into(_db.goals).insert(goal);
    return goal;
  }

  Future<void> update(Goal goal) async {
    final existing = await getById(goal.id);
    if (existing == null) {
      throw NotFoundException('Goal ${goal.id} was not found.');
    }
    final updated = goal.copyWith(
      title: ValidationRules.validateTitle(goal.title),
      createdAt: existing.createdAt,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );
    ValidationRules.validateDate(updated.targetDate, field: 'Target date');
    await (_db.update(
      _db.goals,
    )..where((t) => t.id.equals(goal.id))).write(updated.toCompanion(false));
  }

  Future<void> deleteOrArchive(String id) async {
    final goal = await getById(id);
    if (goal == null) {
      throw NotFoundException('Goal $id was not found.');
    }
    try {
      await (_db.delete(_db.goals)..where((t) => t.id.equals(id))).go();
    } catch (error) {
      if (error.toString().contains('FOREIGN KEY constraint failed')) {
        throw const ConflictException(
          'Goal has subjects and cannot be deleted. Archive it instead.',
        );
      }
      rethrow;
    }
  }
}
