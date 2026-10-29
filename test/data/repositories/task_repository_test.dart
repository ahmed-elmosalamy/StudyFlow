import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:studyflow/core/validation.dart';
import 'package:studyflow/data/database/app_database.dart';
import 'package:studyflow/data/database/tables.dart';
import 'package:studyflow/data/repositories/goal_repository.dart';
import 'package:studyflow/data/repositories/subject_repository.dart';
import 'package:studyflow/data/repositories/task_repository.dart';
import 'package:studyflow/data/repositories/topic_repository.dart';

void main() {
  late AppDatabase db;
  late TaskRepository tasks;
  late String topicId;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    tasks = TaskRepository(db);
    final goals = GoalRepository(db);
    final subjects = SubjectRepository(db);
    final topics = TopicRepository(db);

    final goal = await goals.insert(title: 'Learn Spanish');
    final subject = await subjects.insert(goalId: goal.id, title: 'Grammar');
    final topic = await topics.insert(
      subjectId: subject.id,
      title: 'Present tense',
    );
    topicId = topic.id;
  });

  tearDown(() async {
    await db.close();
  });

  test('creates, updates, reads, and deletes a task', () async {
    final created = await tasks.insert(
      topicId: topicId,
      title: 'Read chapter 1',
      estimateMinutes: 50,
    );
    expect(created.title, 'Read chapter 1');
    expect(created.remainingMinutes, 50);
    expect(created.kind, TaskKind.study);
    expect(created.priority, 1);
    expect(created.status, TaskStatus.open);

    final fetched = await tasks.getById(created.id);
    expect(fetched?.estimateMinutes, 50);

    await tasks.update(
      created.copyWith(
        title: 'Read chapter 2',
        estimateMinutes: 60,
        remainingMinutes: 40,
      ),
    );
    final updated = await tasks.getById(created.id);
    expect(updated?.title, 'Read chapter 2');
    expect(updated?.estimateMinutes, 60);
    expect(updated?.remainingMinutes, 40);

    await tasks.deleteOrArchive(created.id);
    expect(await tasks.getById(created.id), isNull);
  });

  test(
    'rejects invalid estimates, priorities, and remaining minutes',
    () async {
      await expectLater(
        tasks.insert(
          topicId: topicId,
          title: 'Invalid estimate',
          estimateMinutes: 0,
        ),
        throwsA(isA<ValidationException>()),
      );
      await expectLater(
        tasks.insert(
          topicId: topicId,
          title: 'Invalid priority',
          priority: 3,
          estimateMinutes: 30,
        ),
        throwsA(isA<ValidationException>()),
      );
      await expectLater(
        tasks.insert(
          topicId: topicId,
          title: 'Invalid remaining',
          estimateMinutes: 30,
          remainingMinutes: 31,
        ),
        throwsA(isA<ValidationException>()),
      );
    },
  );

  test('revision tasks require a revision stage', () async {
    await expectLater(
      tasks.insert(
        topicId: topicId,
        title: 'Revise',
        kind: TaskKind.revision,
        estimateMinutes: 25,
      ),
      throwsA(isA<ValidationException>()),
    );

    final revision = await tasks.insert(
      topicId: topicId,
      title: 'Revise',
      kind: TaskKind.revision,
      estimateMinutes: 25,
      revisionStage: 0,
    );
    expect(revision.kind, TaskKind.revision);
    expect(revision.revisionStage, 0);
  });

  test('throws NotFoundException for a missing task', () async {
    final task = await tasks.insert(
      topicId: topicId,
      title: 'Temporary',
      estimateMinutes: 30,
    );
    await tasks.deleteOrArchive(task.id);

    await expectLater(
      tasks.update(task.copyWith(title: 'Again')),
      throwsA(isA<NotFoundException>()),
    );
    await expectLater(
      tasks.deleteOrArchive(task.id),
      throwsA(isA<NotFoundException>()),
    );
  });
}
