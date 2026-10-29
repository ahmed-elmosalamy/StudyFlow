import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../core/validation.dart';
import '../database/app_database.dart';
import '../database/tables.dart';

class TopicRepository {
  TopicRepository(this._db);

  final AppDatabase _db;

  static const _uuid = Uuid();

  Stream<List<Topic>> watchAll() {
    return (_db.select(_db.topics)..orderBy([
          (t) => OrderingTerm.asc(t.sortOrder),
          (t) => OrderingTerm.asc(t.createdAt),
        ]))
        .watch();
  }

  Future<Topic?> getById(String id) {
    return (_db.select(
      _db.topics,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
  }

  Future<Topic> insert({
    required String subjectId,
    required String title,
    String? notes,
    TopicStatus status = TopicStatus.not_started,
    String? learnedOn,
    String? revisionCycleStartedOn,
    int sortOrder = 0,
  }) async {
    final validatedTitle = ValidationRules.validateTitle(title);
    ValidationRules.validateDate(learnedOn, field: 'Learned date');
    ValidationRules.validateDate(
      revisionCycleStartedOn,
      field: 'Revision cycle date',
    );
    final now = DateTime.now().millisecondsSinceEpoch;
    final topic = Topic(
      id: _uuid.v4(),
      subjectId: subjectId,
      title: validatedTitle,
      notes: notes,
      status: status,
      learnedOn: learnedOn,
      revisionCycleStartedOn: revisionCycleStartedOn,
      sortOrder: sortOrder,
      createdAt: now,
      updatedAt: now,
    );
    await _db.into(_db.topics).insert(topic);
    return topic;
  }

  Future<void> update(Topic topic) async {
    final existing = await getById(topic.id);
    if (existing == null) {
      throw NotFoundException('Topic ${topic.id} was not found.');
    }
    final updated = topic.copyWith(
      title: ValidationRules.validateTitle(topic.title),
      createdAt: existing.createdAt,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );
    ValidationRules.validateDate(updated.learnedOn, field: 'Learned date');
    ValidationRules.validateDate(
      updated.revisionCycleStartedOn,
      field: 'Revision cycle date',
    );
    await (_db.update(
      _db.topics,
    )..where((t) => t.id.equals(topic.id))).write(updated.toCompanion(false));
  }

  Future<void> deleteOrArchive(String id) async {
    final topic = await getById(id);
    if (topic == null) {
      throw NotFoundException('Topic $id was not found.');
    }
    try {
      await (_db.delete(_db.topics)..where((t) => t.id.equals(id))).go();
    } catch (error) {
      if (error.toString().contains('FOREIGN KEY constraint failed')) {
        throw const ConflictException(
          'Topic has tasks and cannot be deleted. Archive it instead.',
        );
      }
      rethrow;
    }
  }
}
