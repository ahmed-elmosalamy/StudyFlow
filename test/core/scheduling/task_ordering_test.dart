import 'package:flutter_test/flutter_test.dart';
import 'package:studyflow/core/scheduling/scheduling_models.dart';
import 'package:studyflow/core/scheduling/task_ordering.dart';
import 'package:studyflow/core/time/local_date.dart';

void main() {
  final today = LocalDate(2026, 10, 29);

  test('orders dated tasks by effective deadline and tie-breakers', () {
    final tasks = [
      _task(
        'far',
        deadline: LocalDate(2026, 11, 1),
        priority: TaskPriority.high,
      ),
      _task(
        'today-low',
        deadline: today,
        priority: TaskPriority.low,
        createdAt: 1,
      ),
      _task('today-normal-late', deadline: today, createdAt: 10),
      _task('today-normal-early-b', deadline: today, createdAt: 5),
      _task('today-normal-early-a', deadline: today, createdAt: 5),
      _task('overdue-normal', deadline: LocalDate(2026, 10, 20), createdAt: 1),
      _task(
        'today-high',
        deadline: today,
        priority: TaskPriority.high,
        createdAt: 100,
      ),
      _task(
        'undated-revision',
        kind: TaskKind.revision,
        priority: TaskPriority.high,
      ),
    ];

    final sorted = sortTasks(tasks, today);

    expect(sorted.map((task) => task.id).toList(), [
      'today-high',
      'overdue-normal',
      'today-normal-early-a',
      'today-normal-early-b',
      'today-normal-late',
      'today-low',
      'far',
      'undated-revision',
    ]);
  });

  test('orders undated tasks with revisions before studies', () {
    final tasks = [
      _task('study-high', priority: TaskPriority.high, createdAt: 1),
      _task(
        'revision-low',
        kind: TaskKind.revision,
        priority: TaskPriority.low,
        createdAt: 100,
      ),
      _task('revision-normal-late', kind: TaskKind.revision, createdAt: 50),
      _task('revision-normal-early-b', kind: TaskKind.revision, createdAt: 10),
      _task('revision-normal-early-a', kind: TaskKind.revision, createdAt: 10),
      _task('study-normal', createdAt: 0),
    ];

    final sorted = sortTasks(tasks, today);

    expect(sorted.map((task) => task.id).toList(), [
      'revision-normal-early-a',
      'revision-normal-early-b',
      'revision-normal-late',
      'revision-low',
      'study-high',
      'study-normal',
    ]);
  });

  test('treats overdue deadlines as today for ordering', () {
    final tasks = [
      _task(
        'overdue-low',
        deadline: LocalDate(2026, 10, 20),
        priority: TaskPriority.low,
        createdAt: 1,
      ),
      _task(
        'today-high',
        deadline: today,
        priority: TaskPriority.high,
        createdAt: 100,
      ),
      _task(
        'tomorrow-high',
        deadline: today.addDays(1),
        priority: TaskPriority.high,
        createdAt: 0,
      ),
    ];

    final sorted = sortTasks(tasks, today);

    expect(sorted.map((task) => task.id).toList(), [
      'today-high',
      'overdue-low',
      'tomorrow-high',
    ]);
  });
}

EngineTask _task(
  String id, {
  TaskKind kind = TaskKind.study,
  TaskPriority priority = TaskPriority.normal,
  int remainingMinutes = 60,
  LocalDate? deadline,
  LocalDate? notBefore,
  int createdAt = 0,
}) {
  return EngineTask(
    id: id,
    kind: kind,
    priority: priority,
    remainingMinutes: remainingMinutes,
    deadline: deadline,
    notBefore: notBefore,
    createdAt: createdAt,
  );
}
