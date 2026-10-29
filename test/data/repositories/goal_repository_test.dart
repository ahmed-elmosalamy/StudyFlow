import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:studyflow/core/validation.dart';
import 'package:studyflow/data/database/app_database.dart';
import 'package:studyflow/data/database/tables.dart';
import 'package:studyflow/data/repositories/goal_repository.dart';
import 'package:studyflow/data/repositories/subject_repository.dart';

void main() {
  late AppDatabase db;
  late GoalRepository goals;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    goals = GoalRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  test('creates, updates, reads, and deletes a goal', () async {
    final created = await goals.insert(title: '  Learn Spanish  ');
    expect(created.title, 'Learn Spanish');
    expect(created.status, GoalStatus.active);

    final fetched = await goals.getById(created.id);
    expect(fetched?.title, 'Learn Spanish');

    await goals.update(created.copyWith(title: 'Learn Spanish A1'));
    final updated = await goals.getById(created.id);
    expect(updated?.title, 'Learn Spanish A1');
    expect(updated?.updatedAt, greaterThanOrEqualTo(created.updatedAt));

    await goals.deleteOrArchive(created.id);
    expect(await goals.getById(created.id), isNull);
    expect(await goals.watchAll().first, isEmpty);
  });

  test('rejects invalid titles', () async {
    await expectLater(
      goals.insert(title: '   '),
      throwsA(isA<ValidationException>()),
    );
    await expectLater(
      goals.insert(title: 'a' * 121),
      throwsA(isA<ValidationException>()),
    );
  });

  test('throws NotFoundException for missing ids', () async {
    final goal = await goals.insert(title: 'Temporary');
    await goals.deleteOrArchive(goal.id);

    await expectLater(
      goals.update(goal.copyWith(title: 'Again')),
      throwsA(isA<NotFoundException>()),
    );
    await expectLater(
      goals.deleteOrArchive(goal.id),
      throwsA(isA<NotFoundException>()),
    );
  });

  test('deleting a goal with subjects throws ConflictException', () async {
    final goal = await goals.insert(title: 'Learn Spanish');
    final subjects = SubjectRepository(db);
    await subjects.insert(goalId: goal.id, title: 'Grammar');

    await expectLater(
      goals.deleteOrArchive(goal.id),
      throwsA(isA<ConflictException>()),
    );
    expect(await goals.getById(goal.id), isNotNull);
  });
}
