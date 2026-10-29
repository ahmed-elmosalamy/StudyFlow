// Enum names are stored verbatim by textEnum, so snake_case is required here.
// ignore_for_file: constant_identifier_names

import 'package:drift/drift.dart';

enum GoalStatus { active, completed, archived }

enum SubjectStatus { active, archived }

enum TopicStatus { not_started, learning, learned, archived }

enum TaskKind { study, revision }

enum TaskStatus { open, completed, cancelled, archived }

enum SessionStatus { scheduled, in_progress, completed, missed, cancelled }

enum RevisionPreset { off, light, standard }

enum ThemeModeSetting { system, light, dark }

class Goals extends Table {
  TextColumn get id => text()();
  TextColumn get title => text()();
  TextColumn get description => text().nullable()();
  TextColumn get targetDate => text().nullable()();
  IntColumn get colorIndex => integer()();
  TextColumn get status => textEnum<GoalStatus>()();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

@TableIndex(name: 'subjects_goal_status', columns: {#goalId, #status})
class Subjects extends Table {
  TextColumn get id => text()();
  TextColumn get goalId =>
      text().references(Goals, #id, onDelete: KeyAction.restrict)();
  TextColumn get title => text()();
  TextColumn get notes => text().nullable()();
  IntColumn get sortOrder => integer()();
  TextColumn get status => textEnum<SubjectStatus>()();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

@TableIndex(name: 'topics_subject_status', columns: {#subjectId, #status})
class Topics extends Table {
  TextColumn get id => text()();
  TextColumn get subjectId =>
      text().references(Subjects, #id, onDelete: KeyAction.restrict)();
  TextColumn get title => text()();
  TextColumn get notes => text().nullable()();
  TextColumn get status => textEnum<TopicStatus>()();
  TextColumn get learnedOn => text().nullable()();
  TextColumn get revisionCycleStartedOn => text().nullable()();
  IntColumn get sortOrder => integer()();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

@TableIndex(name: 'tasks_status_deadline', columns: {#status, #deadlineDate})
@TableIndex(name: 'tasks_topic', columns: {#topicId})
@TableIndex.sql(
  'CREATE UNIQUE INDEX tasks_topic_revision_stage_unique ON tasks '
  '(topic_id, revision_stage) WHERE revision_stage IS NOT NULL',
)
class Tasks extends Table {
  TextColumn get id => text()();
  TextColumn get topicId =>
      text().references(Topics, #id, onDelete: KeyAction.restrict)();
  TextColumn get title => text()();
  TextColumn get notes => text().nullable()();
  TextColumn get kind => textEnum<TaskKind>()();
  IntColumn get priority => integer()();
  IntColumn get estimateMinutes => integer()();
  IntColumn get remainingMinutes => integer()();
  TextColumn get deadlineDate => text().nullable()();
  TextColumn get notBeforeDate => text().nullable()();
  IntColumn get revisionStage => integer().nullable()();
  TextColumn get status => textEnum<TaskStatus>()();
  IntColumn get completedAt => integer().nullable()();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

@TableIndex(
  name: 'study_sessions_date_start',
  columns: {#sessionDate, #startMinute},
)
@TableIndex(name: 'study_sessions_task_status', columns: {#taskId, #status})
class StudySessions extends Table {
  TextColumn get id => text()();
  TextColumn get taskId =>
      text().references(Tasks, #id, onDelete: KeyAction.restrict)();
  TextColumn get sessionDate => text()();
  IntColumn get startMinute => integer()();
  IntColumn get plannedMinutes => integer()();
  IntColumn get actualMinutes => integer().nullable()();
  TextColumn get status => textEnum<SessionStatus>()();
  IntColumn get startedAtUtc => integer().nullable()();
  IntColumn get completedAtUtc => integer().nullable()();
  IntColumn get timerAccumulatedSeconds =>
      integer().withDefault(const Constant(0))();
  IntColumn get timerResumedAtUtc => integer().nullable()();
  TextColumn get note => text().nullable()();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<String> get customConstraints => [
    'CHECK (start_minute >= 0 AND start_minute <= 1439)',
    'CHECK (planned_minutes > 0)',
    'CHECK (start_minute + planned_minutes <= 1440)',
  ];
}

@TableIndex(name: 'availability_windows_weekday', columns: {#weekday})
class AvailabilityWindows extends Table {
  TextColumn get id => text()();
  IntColumn get weekday => integer()();
  IntColumn get startMinute => integer()();
  IntColumn get endMinute => integer()();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<String> get customConstraints => [
    'CHECK (weekday >= 1 AND weekday <= 7)',
    'CHECK (start_minute >= 0)',
    'CHECK (end_minute <= 1440)',
    'CHECK (end_minute > start_minute)',
  ];
}

class AppSettings extends Table {
  IntColumn get id => integer().withDefault(const Constant(1))();
  IntColumn get dailyLimitMinutes =>
      integer().withDefault(const Constant(120))();
  IntColumn get blockLengthMinutes =>
      integer().withDefault(const Constant(50))();
  IntColumn get minSessionMinutes =>
      integer().withDefault(const Constant(15))();
  IntColumn get breakMinutes => integer().withDefault(const Constant(10))();
  IntColumn get horizonDays => integer().withDefault(const Constant(14))();
  TextColumn get revisionPreset =>
      textEnum<RevisionPreset>().withDefault(const Constant('standard'))();
  IntColumn get revisionLengthMinutes =>
      integer().withDefault(const Constant(25))();
  IntColumn get autoReplan => integer().withDefault(const Constant(1))();
  TextColumn get themeMode =>
      textEnum<ThemeModeSetting>().withDefault(const Constant('system'))();
  IntColumn get dynamicColor => integer().withDefault(const Constant(1))();
  IntColumn get setupComplete => integer().withDefault(const Constant(0))();
  IntColumn get lastPlanAt => integer().nullable()();
  IntColumn get planStale => integer().withDefault(const Constant(0))();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<String> get customConstraints => ['CHECK (id = 1)'];
}
