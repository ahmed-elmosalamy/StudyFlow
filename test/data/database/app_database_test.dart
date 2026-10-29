import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:studyflow/data/database/app_database.dart';
import 'package:studyflow/data/database/tables.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  test('inserts the hierarchy and the settings singleton', () async {
    await _insertHierarchy(db);
    await db
        .into(db.appSettings)
        .insert(AppSettingsCompanion.insert(createdAt: _now, updatedAt: _now));

    final goal = await (db.select(
      db.goals,
    )..where((t) => t.id.equals('goal-1'))).getSingle();
    expect(goal.status, GoalStatus.active);

    final task = await db.select(db.tasks).getSingle();
    expect(task.kind, TaskKind.study);
    expect(task.status, TaskStatus.open);
    expect(task.revisionStage, isNull);

    final settings = await db.select(db.appSettings).getSingle();
    expect(settings.id, 1);
    expect(settings.autoReplan, 1);
    expect(settings.revisionPreset, RevisionPreset.standard);
    expect(settings.themeMode, ThemeModeSetting.system);
  });

  test('app_settings rejects a second row', () async {
    await db
        .into(db.appSettings)
        .insert(AppSettingsCompanion.insert(createdAt: _now, updatedAt: _now));

    await expectLater(
      db
          .into(db.appSettings)
          .insert(
            AppSettingsCompanion.insert(
              id: const Value(2),
              createdAt: _now,
              updatedAt: _now,
            ),
          ),
      throwsA(isA<Exception>()),
    );
  });

  test('deleting a goal with a subject is restricted', () async {
    await _insertHierarchy(db);

    await expectLater(
      (db.delete(db.goals)..where((t) => t.id.equals('goal-1'))).go(),
      throwsA(isA<Exception>()),
    );

    expect(await db.select(db.goals).get(), hasLength(1));
    expect(await db.select(db.subjects).get(), hasLength(1));
  });
}

const _now = 1760000000000;

Future<void> _insertHierarchy(AppDatabase db) async {
  await db
      .into(db.goals)
      .insert(
        GoalsCompanion.insert(
          id: 'goal-1',
          title: 'Learn Spanish',
          colorIndex: 0,
          status: GoalStatus.active,
          createdAt: _now,
          updatedAt: _now,
        ),
      );
  await db
      .into(db.subjects)
      .insert(
        SubjectsCompanion.insert(
          id: 'subject-1',
          goalId: 'goal-1',
          title: 'Grammar',
          sortOrder: 0,
          status: SubjectStatus.active,
          createdAt: _now,
          updatedAt: _now,
        ),
      );
  await db
      .into(db.topics)
      .insert(
        TopicsCompanion.insert(
          id: 'topic-1',
          subjectId: 'subject-1',
          title: 'Present tense',
          status: TopicStatus.learning,
          sortOrder: 0,
          createdAt: _now,
          updatedAt: _now,
        ),
      );
  await db
      .into(db.tasks)
      .insert(
        TasksCompanion.insert(
          id: 'task-1',
          topicId: 'topic-1',
          title: 'Study chapter 1',
          kind: TaskKind.study,
          priority: 1,
          estimateMinutes: 50,
          remainingMinutes: 50,
          status: TaskStatus.open,
          createdAt: _now,
          updatedAt: _now,
        ),
      );
}
