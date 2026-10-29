import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../core/validation.dart';
import '../database/app_database.dart';
import '../database/tables.dart';

class SubjectRepository {
  SubjectRepository(this._db);

  final AppDatabase _db;

  static const _uuid = Uuid();

  Stream<List<Subject>> watchAll() {
    return (_db.select(_db.subjects)..orderBy([
          (t) => OrderingTerm.asc(t.sortOrder),
          (t) => OrderingTerm.asc(t.createdAt),
        ]))
        .watch();
  }

  Future<Subject?> getById(String id) {
    return (_db.select(
      _db.subjects,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
  }

  Future<Subject> insert({
    required String goalId,
    required String title,
    String? notes,
    int sortOrder = 0,
    SubjectStatus status = SubjectStatus.active,
  }) async {
    final validatedTitle = ValidationRules.validateTitle(title);
    final now = DateTime.now().millisecondsSinceEpoch;
    final subject = Subject(
      id: _uuid.v4(),
      goalId: goalId,
      title: validatedTitle,
      notes: notes,
      sortOrder: sortOrder,
      status: status,
      createdAt: now,
      updatedAt: now,
    );
    await _db.into(_db.subjects).insert(subject);
    return subject;
  }

  Future<void> update(Subject subject) async {
    final existing = await getById(subject.id);
    if (existing == null) {
      throw NotFoundException('Subject ${subject.id} was not found.');
    }
    final updated = subject.copyWith(
      title: ValidationRules.validateTitle(subject.title),
      createdAt: existing.createdAt,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );
    await (_db.update(
      _db.subjects,
    )..where((t) => t.id.equals(subject.id))).write(updated.toCompanion(false));
  }

  Future<void> deleteOrArchive(String id) async {
    final subject = await getById(id);
    if (subject == null) {
      throw NotFoundException('Subject $id was not found.');
    }
    try {
      await (_db.delete(_db.subjects)..where((t) => t.id.equals(id))).go();
    } catch (error) {
      if (error.toString().contains('FOREIGN KEY constraint failed')) {
        throw const ConflictException(
          'Subject has topics and cannot be deleted. Archive it instead.',
        );
      }
      rethrow;
    }
  }
}
