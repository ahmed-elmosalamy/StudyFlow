import 'package:flutter_test/flutter_test.dart';
import 'package:studyflow/core/scheduling/scheduling_models.dart';
import 'package:studyflow/core/scheduling/study_scheduler.dart';
import 'package:studyflow/core/time/local_date.dart';

const _defaultSettings = SchedulingSettings(
  dailyLimitMinutes: 120,
  blockLengthMinutes: 50,
  minSessionMinutes: 15,
  breakMinutes: 10,
);

void main() {
  test('single task in a single window that fits exactly', () {
    final result = generatePlan(
      _input(
        today: LocalDate(2026, 11, 2),
        horizonDays: 1,
        availability: _windowsFor([1], endMinute: 1130),
        tasks: [_task('A', remainingMinutes: 50)],
      ),
    );

    expect(_descriptions(result), ['2026-11-02 1080 50 A']);
    expect(_allocation(result, 'A').newlyPlannedMinutes, 50);
    expect(_allocation(result, 'A').unscheduledMinutes, 0);
    expect(result.issues, isEmpty);
    expect(result.daySummaries.single.plannedMinutes, 50);
    expect(result.daySummaries.single.remainingCapacity, 70);
  });

  test('daily limit reached mid-task continues on the next day', () {
    final result = generatePlan(
      _input(
        today: LocalDate(2026, 11, 2),
        horizonDays: 2,
        availability: _windowsFor([1, 2]),
        tasks: [_task('A', remainingMinutes: 150)],
        settings: const SchedulingSettings(
          dailyLimitMinutes: 100,
          blockLengthMinutes: 50,
          minSessionMinutes: 15,
          breakMinutes: 10,
        ),
      ),
    );

    expect(_descriptions(result), [
      '2026-11-02 1080 50 A',
      '2026-11-02 1140 50 A',
      '2026-11-03 1080 50 A',
    ]);
    expect(_allocation(result, 'A').newlyPlannedMinutes, 150);
    expect(_allocation(result, 'A').unscheduledMinutes, 0);
    expect(result.issues, isEmpty);
    expect(result.daySummaries[0].plannedMinutes, 100);
    expect(result.daySummaries[0].remainingCapacity, 0);
    expect(result.daySummaries[1].plannedMinutes, 50);
    expect(result.daySummaries[1].remainingCapacity, 50);
  });

  test('completed minutes consume part of the daily limit', () {
    final monday = LocalDate(2026, 11, 2);
    final result = generatePlan(
      _input(
        today: monday,
        horizonDays: 1,
        availability: _windowsFor([1]),
        tasks: [_task('t', remainingMinutes: 60)],
        lockedSessions: [
          LockedSession(
            taskId: 'old',
            date: monday,
            startMinute: 1080,
            plannedMinutes: 50,
            status: SessionStatus.completed,
            actualMinutes: 80,
          ),
        ],
      ),
    );

    expect(_descriptions(result), ['2026-11-02 1170 40 t']);
    expect(_allocation(result, 't').newlyPlannedMinutes, 40);
    expect(_allocation(result, 't').unscheduledMinutes, 20);
    expect(result.issues.single.type, SchedulingIssueType.horizonBacklog);
    expect(result.daySummaries.single.plannedMinutes, 40);
    expect(result.daySummaries.single.remainingCapacity, 0);
  });

  test('in-progress session locks a slot and reserves task minutes', () {
    final monday = LocalDate(2026, 11, 2);
    final result = generatePlan(
      _input(
        today: monday,
        horizonDays: 1,
        availability: _windowsFor([1]),
        tasks: [_task('A', remainingMinutes: 80)],
        lockedSessions: [
          LockedSession(
            taskId: 'A',
            date: monday,
            startMinute: 1080,
            plannedMinutes: 50,
            status: SessionStatus.inProgress,
            elapsedMinutes: 20,
          ),
        ],
      ),
    );

    expect(_descriptions(result), ['2026-11-02 1140 30 A']);
    final allocation = _allocation(result, 'A');
    expect(allocation.reservedActiveMinutes, 50);
    expect(allocation.newlyPlannedMinutes, 30);
    expect(allocation.unscheduledMinutes, 0);
    expect(result.issues, isEmpty);
    expect(result.daySummaries.single.plannedMinutes, 30);
    expect(result.daySummaries.single.remainingCapacity, 40);
  });

  test('active-today session is retained and not double-planned', () {
    final monday = LocalDate(2026, 11, 2);
    final result = generatePlan(
      _input(
        today: monday,
        horizonDays: 1,
        availability: _windowsFor([1]),
        tasks: [_task('A', remainingMinutes: 50)],
        lockedSessions: [
          LockedSession(
            taskId: 'A',
            date: monday,
            startMinute: 1080,
            plannedMinutes: 50,
            status: SessionStatus.activeScheduledToday,
          ),
        ],
      ),
    );

    expect(result.sessions, isEmpty);
    final allocation = _allocation(result, 'A');
    expect(allocation.reservedActiveMinutes, 50);
    expect(allocation.newlyPlannedMinutes, 0);
    expect(allocation.unscheduledMinutes, 0);
    expect(result.issues, isEmpty);
    expect(result.daySummaries.single.plannedMinutes, 0);
    expect(result.daySummaries.single.remainingCapacity, 70);
  });

  test('break is enforced between sessions within a window', () {
    final result = generatePlan(
      _input(
        today: LocalDate(2026, 11, 2),
        horizonDays: 1,
        availability: _windowsFor([1]),
        tasks: [
          _task('A', remainingMinutes: 50, createdAt: 0),
          _task('B', remainingMinutes: 50, createdAt: 1),
          _task('C', remainingMinutes: 50, createdAt: 2),
        ],
        settings: const SchedulingSettings(
          dailyLimitMinutes: 180,
          blockLengthMinutes: 50,
          minSessionMinutes: 15,
          breakMinutes: 10,
        ),
      ),
    );

    expect(_descriptions(result), [
      '2026-11-02 1080 50 A',
      '2026-11-02 1140 50 B',
      '2026-11-02 1200 50 C',
    ]);
    expect(result.daySummaries.single.plannedMinutes, 150);
    expect(result.daySummaries.single.remainingCapacity, 30);
  });

  test('sessions from different tasks never overlap', () {
    final result = generatePlan(
      _input(
        today: LocalDate(2026, 11, 2),
        horizonDays: 1,
        availability: _windowsFor([1]),
        tasks: [
          _task('A', remainingMinutes: 80, createdAt: 0),
          _task('B', remainingMinutes: 70, createdAt: 1),
        ],
        settings: const SchedulingSettings(
          dailyLimitMinutes: 180,
          blockLengthMinutes: 50,
          minSessionMinutes: 15,
          breakMinutes: 10,
        ),
      ),
    );

    expect(_descriptions(result), [
      '2026-11-02 1080 50 A',
      '2026-11-02 1140 30 A',
      '2026-11-02 1180 50 B',
      '2026-11-02 1240 20 B',
    ]);
    for (var index = 0; index < result.sessions.length - 1; index++) {
      final current = result.sessions[index];
      final next = result.sessions[index + 1];
      expect(
        current.startMinute + current.plannedMinutes <= next.startMinute,
        isTrue,
      );
    }
  });

  test('hard deadline exactly fits without a warning', () {
    final monday = LocalDate(2026, 11, 2);
    final result = generatePlan(
      _input(
        today: monday,
        horizonDays: 7,
        availability: _windowsFor([1]),
        tasks: [_task('A', remainingMinutes: 120, deadline: monday)],
      ),
    );

    expect(_descriptions(result), [
      '2026-11-02 1080 50 A',
      '2026-11-02 1140 50 A',
      '2026-11-02 1200 20 A',
    ]);
    expect(_allocation(result, 'A').unscheduledMinutes, 0);
    expect(result.issues, isEmpty);
  });

  test('hard deadline one minute short reports a deficit of one', () {
    final monday = LocalDate(2026, 11, 2);
    final result = generatePlan(
      _input(
        today: monday,
        horizonDays: 7,
        availability: _windowsFor([1]),
        tasks: [_task('A', remainingMinutes: 121, deadline: monday)],
      ),
    );

    expect(_descriptions(result), [
      '2026-11-02 1080 50 A',
      '2026-11-02 1140 50 A',
      '2026-11-02 1200 20 A',
    ]);
    final issue = result.issues.single;
    expect(issue.type, SchedulingIssueType.impossibleDeadline);
    expect(issue.remainingMinutes, 121);
    expect(issue.scheduledBeforeDeadlineMinutes, 120);
    expect(issue.deficitMinutes, 1);
    expect(issue.availableCapacityBeforeDeadline, 120);
    expect(issue.otherMinutesBeforeDeadline, 0);
    expect(issue.daysAvailableBeforeDeadline, 1);
    expect(issue.suggestedExtraMinutesPerDay, 5);
  });

  test('notBefore blocks early placement and shifts to the next day', () {
    final result = generatePlan(
      _input(
        today: LocalDate(2026, 10, 29),
        horizonDays: 2,
        availability: _windowsFor([4, 5]),
        tasks: [
          _task('A', remainingMinutes: 50, notBefore: LocalDate(2026, 10, 30)),
        ],
      ),
    );

    expect(_descriptions(result), ['2026-10-30 1080 50 A']);
    expect(_allocation(result, 'A').newlyPlannedMinutes, 50);
    expect(result.issues, isEmpty);
  });

  test('revision sorts ahead of undated study but waits for its date', () {
    final result = generatePlan(
      _input(
        today: LocalDate(2026, 10, 29),
        horizonDays: 2,
        availability: _windowsFor([4, 5]),
        tasks: [
          _task('S', remainingMinutes: 40, createdAt: 0),
          _task(
            'R',
            remainingMinutes: 40,
            kind: TaskKind.revision,
            notBefore: LocalDate(2026, 10, 30),
            createdAt: 0,
          ),
        ],
      ),
    );

    expect(_descriptions(result), [
      '2026-10-29 1080 40 S',
      '2026-10-30 1080 40 R',
    ]);
    expect(_allocation(result, 'R').newlyPlannedMinutes, 40);
    expect(_allocation(result, 'S').newlyPlannedMinutes, 40);
    expect(result.issues, isEmpty);
  });

  test('windows on other weekdays do not receive sessions', () {
    final result = generatePlan(
      _input(
        today: LocalDate(2026, 10, 29),
        horizonDays: 4,
        availability: _windowsFor([5]),
        tasks: [_task('A', remainingMinutes: 50)],
      ),
    );

    expect(_descriptions(result), ['2026-10-30 1080 50 A']);
    expect(result.daySummaries, hasLength(4));
    expect(result.issues, isEmpty);
  });

  test('horizon includes today and the last day but not the day after', () {
    final monday = LocalDate(2026, 11, 2);
    final lastDay = monday.addDays(1);
    final result = generatePlan(
      _input(
        today: monday,
        horizonDays: 2,
        availability: _windowsFor([1, 2, 3, 4, 5, 6, 7]),
        tasks: [_task('A', remainingMinutes: 500)],
      ),
    );

    expect(result.sessions, hasLength(6));
    for (final session in result.sessions) {
      expect(session.date.isBefore(monday), isFalse);
      expect(session.date.isAfter(lastDay), isFalse);
    }
    expect(result.daySummaries.map((day) => day.date).toList(), [
      monday,
      lastDay,
    ]);
    expect(result.issues.single.type, SchedulingIssueType.horizonBacklog);
  });

  test('now is rounded up near midnight and spills to the next day', () {
    final result = generatePlan(
      _input(
        today: LocalDate(2026, 10, 29),
        horizonDays: 2,
        availability: [
          const AvailabilityWindow(
            weekday: 4,
            startMinute: 1430,
            endMinute: 1440,
          ),
          const AvailabilityWindow(
            weekday: 5,
            startMinute: 1080,
            endMinute: 1260,
          ),
        ],
        tasks: [_task('A', remainingMinutes: 10)],
        nowMinuteOfDay: 1438,
      ),
    );

    expect(_descriptions(result), ['2026-10-30 1080 10 A']);
    expect(result.issues, isEmpty);
  });

  test('deadline today with an active session leaves no warning', () {
    final monday = LocalDate(2026, 11, 2);
    final result = generatePlan(
      _input(
        today: monday,
        horizonDays: 1,
        availability: _windowsFor([1]),
        tasks: [_task('A', remainingMinutes: 80, deadline: monday)],
        lockedSessions: [
          LockedSession(
            taskId: 'A',
            date: monday,
            startMinute: 1080,
            plannedMinutes: 50,
            status: SessionStatus.activeScheduledToday,
          ),
        ],
      ),
    );

    expect(_descriptions(result), ['2026-11-02 1140 30 A']);
    final allocation = _allocation(result, 'A');
    expect(allocation.reservedActiveMinutes, 50);
    expect(allocation.newlyPlannedMinutes, 30);
    expect(allocation.unscheduledMinutes, 0);
    expect(result.issues, isEmpty);
  });

  test('in-progress elapsed beyond planned expands the lock', () {
    final monday = LocalDate(2026, 11, 2);
    final result = generatePlan(
      _input(
        today: monday,
        horizonDays: 1,
        availability: _windowsFor([1]),
        tasks: [_task('A', remainingMinutes: 60)],
        lockedSessions: [
          LockedSession(
            taskId: 'A',
            date: monday,
            startMinute: 1080,
            plannedMinutes: 50,
            status: SessionStatus.inProgress,
            elapsedMinutes: 70,
          ),
        ],
      ),
    );

    expect(_descriptions(result), ['2026-11-02 1160 10 A']);
    final allocation = _allocation(result, 'A');
    expect(allocation.reservedActiveMinutes, 50);
    expect(allocation.newlyPlannedMinutes, 10);
    expect(result.issues, isEmpty);
    expect(result.daySummaries.single.plannedMinutes, 10);
    expect(result.daySummaries.single.remainingCapacity, 40);
  });

  test(
    'stale in-progress session reserves minutes without consuming today',
    () {
      final monday = LocalDate(2026, 11, 2);
      final result = generatePlan(
        _input(
          today: monday,
          horizonDays: 1,
          availability: _windowsFor([1]),
          tasks: [_task('A', remainingMinutes: 60)],
          lockedSessions: [
            LockedSession(
              taskId: 'A',
              date: monday.addDays(-1),
              startMinute: 1080,
              plannedMinutes: 50,
              status: SessionStatus.inProgress,
              elapsedMinutes: 20,
            ),
          ],
        ),
      );

      expect(_descriptions(result), ['2026-11-02 1080 10 A']);
      final allocation = _allocation(result, 'A');
      expect(allocation.reservedActiveMinutes, 50);
      expect(allocation.newlyPlannedMinutes, 10);
      expect(allocation.unscheduledMinutes, 0);
      expect(result.issues, isEmpty);
      expect(result.daySummaries.single.plannedMinutes, 10);
      expect(result.daySummaries.single.remainingCapacity, 110);
    },
  );

  test('minimum session guard skips a non-final short fragment', () {
    final result = generatePlan(
      _input(
        today: LocalDate(2026, 11, 2),
        horizonDays: 1,
        availability: _windowsFor([1], endMinute: 1090),
        tasks: [_task('A', remainingMinutes: 100)],
      ),
    );

    expect(result.sessions, isEmpty);
    expect(_allocation(result, 'A').unscheduledMinutes, 100);
    final issue = result.issues.single;
    expect(issue.type, SchedulingIssueType.horizonBacklog);
    expect(issue.unscheduledMinutes, 100);
  });

  test('whole task below minimum is scheduled as one short session', () {
    final result = generatePlan(
      _input(
        today: LocalDate(2026, 11, 2),
        horizonDays: 1,
        availability: _windowsFor([1], endMinute: 1090),
        tasks: [_task('A', remainingMinutes: 10)],
      ),
    );

    expect(_descriptions(result), ['2026-11-02 1080 10 A']);
    expect(result.issues, isEmpty);
  });

  test('deadline today with the window already past is impossible', () {
    final monday = LocalDate(2026, 11, 2);
    final result = generatePlan(
      _input(
        today: monday,
        horizonDays: 1,
        availability: _windowsFor([1]),
        tasks: [_task('A', remainingMinutes: 50, deadline: monday)],
        nowMinuteOfDay: 1300,
      ),
    );

    expect(result.sessions, isEmpty);
    expect(result.issues.map((issue) => issue.type).toList(), [
      SchedulingIssueType.noAvailability,
      SchedulingIssueType.impossibleDeadline,
    ]);
    final issue = result.issues[1];
    expect(issue.availableCapacityBeforeDeadline, 0);
    expect(issue.daysAvailableBeforeDeadline, 0);
    expect(issue.deficitMinutes, 50);
    expect(issue.suggestedExtraMinutesPerDay, isNull);
  });
}

SchedulingInput _input({
  required LocalDate today,
  required int horizonDays,
  required List<AvailabilityWindow> availability,
  required List<EngineTask> tasks,
  SchedulingSettings settings = _defaultSettings,
  int nowMinuteOfDay = 1020,
  List<LockedSession> lockedSessions = const [],
}) {
  return SchedulingInput(
    today: today,
    nowMinuteOfDay: nowMinuteOfDay,
    horizonDays: horizonDays,
    settings: settings,
    availability: availability,
    tasks: tasks,
    lockedSessions: lockedSessions,
  );
}

List<AvailabilityWindow> _windowsFor(
  List<int> weekdays, {
  int startMinute = 1080,
  int endMinute = 1260,
}) {
  return [
    for (final weekday in weekdays)
      AvailabilityWindow(
        weekday: weekday,
        startMinute: startMinute,
        endMinute: endMinute,
      ),
  ];
}

EngineTask _task(
  String id, {
  required int remainingMinutes,
  TaskKind kind = TaskKind.study,
  TaskPriority priority = TaskPriority.normal,
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

List<String> _descriptions(PlanResult result) {
  return [
    for (final session in result.sessions)
      '${session.date} ${session.startMinute} '
          '${session.plannedMinutes} ${session.taskId}',
  ];
}

TaskAllocation _allocation(PlanResult result, String taskId) {
  return result.allocations.firstWhere(
    (allocation) => allocation.taskId == taskId,
  );
}
