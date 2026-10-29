import 'package:flutter_test/flutter_test.dart';
import 'package:studyflow/core/scheduling/scheduling_models.dart';
import 'package:studyflow/core/scheduling/study_scheduler.dart';
import 'package:studyflow/core/time/local_date.dart';

void main() {
  final today = LocalDate(2026, 10, 29);

  test('Example B: impossible deadline reports exact warning fields', () {
    final friday = LocalDate(2026, 10, 30);
    final result = generatePlan(
      _input(
        today: today,
        horizonDays: 14,
        availability: _windowsFor([4, 5]),
        tasks: [
          _task(
            'A',
            remainingMinutes: 300,
            priority: TaskPriority.high,
            deadline: friday,
          ),
        ],
      ),
    );

    expect(_descriptions(result), [
      '2026-10-29 1080 50 A',
      '2026-10-29 1140 50 A',
      '2026-10-29 1200 20 A',
      '2026-10-30 1080 50 A',
      '2026-10-30 1140 50 A',
      '2026-10-30 1200 20 A',
    ]);
    expect(result.issues, hasLength(1));
    final issue = result.issues.single;
    expect(issue.type, SchedulingIssueType.impossibleDeadline);
    expect(issue.taskId, 'A');
    expect(issue.deadline, friday);
    expect(issue.remainingMinutes, 300);
    expect(issue.reservedActiveMinutes, 0);
    expect(issue.scheduledBeforeDeadlineMinutes, 240);
    expect(issue.deficitMinutes, 60);
    expect(issue.availableCapacityBeforeDeadline, 240);
    expect(issue.otherMinutesBeforeDeadline, 0);
    expect(issue.daysAvailableBeforeDeadline, 2);
    expect(issue.suggestedExtraMinutesPerDay, 30);
    for (final session in result.sessions) {
      expect(session.date.isAfter(friday), isFalse);
    }
  });

  test('overdue task schedules ASAP and is flagged', () {
    final result = generatePlan(
      _input(
        today: today,
        horizonDays: 2,
        availability: _windowsFor([4, 5]),
        tasks: [
          _task('A', remainingMinutes: 100, deadline: LocalDate(2026, 10, 28)),
        ],
      ),
    );

    expect(_descriptions(result), [
      '2026-10-29 1080 50 A',
      '2026-10-29 1140 50 A',
    ]);
    expect(result.issues, hasLength(1));
    final issue = result.issues.single;
    expect(issue.type, SchedulingIssueType.overdueTask);
    expect(issue.taskId, 'A');
    expect(issue.deadline, LocalDate(2026, 10, 28));
    expect(issue.remainingMinutes, 100);
    expect(issue.scheduledMinutes, 100);
    expect(issue.unscheduledMinutes, 0);
    expect(issue.daysOverdue, 1);
  });

  test('overdue task keeps a warning when work remains unscheduled', () {
    final result = generatePlan(
      _input(
        today: today,
        horizonDays: 2,
        availability: _windowsFor([4, 5]),
        tasks: [
          _task('B', remainingMinutes: 500, deadline: LocalDate(2026, 10, 26)),
        ],
      ),
    );

    expect(result.sessions, hasLength(6));
    final issue = result.issues.single;
    expect(issue.type, SchedulingIssueType.overdueTask);
    expect(issue.remainingMinutes, 500);
    expect(issue.scheduledMinutes, 240);
    expect(issue.unscheduledMinutes, 260);
    expect(issue.daysOverdue, 3);
  });

  test('no windows returns NoAvailability', () {
    final result = generatePlan(
      _input(
        today: today,
        horizonDays: 7,
        availability: const [],
        tasks: const [],
      ),
    );

    expect(result.sessions, isEmpty);
    expect(result.allocations, isEmpty);
    expect(result.daySummaries, hasLength(7));
    expect(result.issues, hasLength(1));
    expect(result.issues.single.type, SchedulingIssueType.noAvailability);
  });

  test('NoAvailability comes before task backlog warnings', () {
    final result = generatePlan(
      _input(
        today: today,
        horizonDays: 7,
        availability: const [],
        tasks: [_task('A', remainingMinutes: 60)],
      ),
    );

    expect(result.sessions, isEmpty);
    expect(result.issues.map((issue) => issue.type).toList(), [
      SchedulingIssueType.noAvailability,
      SchedulingIssueType.horizonBacklog,
    ]);
    expect(result.issues[1].taskId, 'A');
    expect(result.issues[1].unscheduledMinutes, 60);
  });

  test('deferred task reports DeferredBeyondHorizon only', () {
    final notBefore = LocalDate(2026, 11, 8);
    final result = generatePlan(
      _input(
        today: today,
        horizonDays: 7,
        availability: _windowsFor([4, 5]),
        tasks: [_task('A', remainingMinutes: 60, notBefore: notBefore)],
      ),
    );

    expect(result.sessions, isEmpty);
    expect(result.issues, hasLength(1));
    final issue = result.issues.single;
    expect(issue.type, SchedulingIssueType.deferredBeyondHorizon);
    expect(issue.taskId, 'A');
    expect(issue.notBefore, notBefore);
    expect(issue.remainingMinutes, 60);
  });

  test('no-deadline task reports HorizonBacklog at horizon end', () {
    final result = generatePlan(
      _input(
        today: LocalDate(2026, 11, 2),
        horizonDays: 1,
        availability: _windowsFor([1]),
        tasks: [_task('A', remainingMinutes: 200)],
      ),
    );

    expect(_descriptions(result), [
      '2026-11-02 1080 50 A',
      '2026-11-02 1140 50 A',
      '2026-11-02 1200 20 A',
    ]);
    final issue = result.issues.single;
    expect(issue.type, SchedulingIssueType.horizonBacklog);
    expect(issue.taskId, 'A');
    expect(issue.remainingMinutes, 200);
    expect(issue.scheduledMinutes, 120);
    expect(issue.unscheduledMinutes, 80);
    expect(issue.deadline, isNull);
  });

  test('final short remainder is not a backlog', () {
    final result = generatePlan(
      _input(
        today: LocalDate(2026, 11, 2),
        horizonDays: 1,
        availability: _windowsFor([1]),
        tasks: [_task('A', remainingMinutes: 10)],
      ),
    );

    expect(_descriptions(result), ['2026-11-02 1080 10 A']);
    expect(result.issues, isEmpty);
  });

  test('far deadline leftover is BeyondHorizon, not impossible', () {
    final deadline = LocalDate(2026, 11, 22);
    final result = generatePlan(
      _input(
        today: LocalDate(2026, 11, 2),
        horizonDays: 2,
        availability: _windowsFor([1, 2]),
        tasks: [_task('A', remainingMinutes: 500, deadline: deadline)],
      ),
    );

    expect(result.sessions, hasLength(6));
    final issue = result.issues.single;
    expect(issue.type, SchedulingIssueType.beyondHorizon);
    expect(issue.type, isNot(SchedulingIssueType.impossibleDeadline));
    expect(issue.taskId, 'A');
    expect(issue.deadline, deadline);
    expect(issue.remainingMinutes, 500);
    expect(issue.scheduledMinutes, 240);
    expect(issue.unscheduledMinutes, 260);
  });

  test('suggested extra minutes rounds up to five', () {
    final result = generatePlan(
      _input(
        today: today,
        horizonDays: 14,
        availability: _windowsFor([4, 5]),
        tasks: [
          _task('A', remainingMinutes: 301, deadline: LocalDate(2026, 10, 30)),
        ],
      ),
    );

    final issue = result.issues.single;
    expect(issue.type, SchedulingIssueType.impossibleDeadline);
    expect(issue.deficitMinutes, 61);
    expect(issue.daysAvailableBeforeDeadline, 2);
    expect(issue.suggestedExtraMinutesPerDay, 35);
  });

  test('task issues follow task order after the global issue', () {
    final result = generatePlan(
      _input(
        today: today,
        horizonDays: 7,
        availability: const [],
        tasks: [
          _task('B', remainingMinutes: 60),
          _task('A', remainingMinutes: 50, deadline: LocalDate(2026, 10, 27)),
        ],
      ),
    );

    expect(result.issues.map((issue) => issue.type).toList(), [
      SchedulingIssueType.noAvailability,
      SchedulingIssueType.overdueTask,
      SchedulingIssueType.horizonBacklog,
    ]);
    expect(result.issues[1].taskId, 'A');
    expect(result.issues[1].daysOverdue, 2);
    expect(result.issues[2].taskId, 'B');
  });
}

SchedulingInput _input({
  required LocalDate today,
  required int horizonDays,
  required List<AvailabilityWindow> availability,
  required List<EngineTask> tasks,
  int nowMinuteOfDay = 1020,
  List<LockedSession> lockedSessions = const [],
}) {
  return SchedulingInput(
    today: today,
    nowMinuteOfDay: nowMinuteOfDay,
    horizonDays: horizonDays,
    settings: const SchedulingSettings(
      dailyLimitMinutes: 120,
      blockLengthMinutes: 50,
      minSessionMinutes: 15,
      breakMinutes: 10,
    ),
    availability: availability,
    tasks: tasks,
    lockedSessions: lockedSessions,
  );
}

List<AvailabilityWindow> _windowsFor(List<int> weekdays) {
  return [
    for (final weekday in weekdays)
      AvailabilityWindow(weekday: weekday, startMinute: 1080, endMinute: 1260),
  ];
}

EngineTask _task(
  String id, {
  required int remainingMinutes,
  TaskPriority priority = TaskPriority.normal,
  LocalDate? deadline,
  LocalDate? notBefore,
}) {
  return EngineTask(
    id: id,
    kind: TaskKind.study,
    priority: priority,
    remainingMinutes: remainingMinutes,
    deadline: deadline,
    notBefore: notBefore,
    createdAt: 0,
  );
}

List<String> _descriptions(PlanResult result) {
  return [
    for (final session in result.sessions)
      '${session.date} ${session.startMinute} '
          '${session.plannedMinutes} ${session.taskId}',
  ];
}
