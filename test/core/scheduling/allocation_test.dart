import 'package:flutter_test/flutter_test.dart';
import 'package:studyflow/core/scheduling/scheduling_models.dart';
import 'package:studyflow/core/scheduling/study_scheduler.dart';
import 'package:studyflow/core/time/local_date.dart';

void main() {
  const settings = SchedulingSettings(
    dailyLimitMinutes: 120,
    blockLengthMinutes: 50,
    minSessionMinutes: 15,
    breakMinutes: 10,
  );
  final today = LocalDate(2026, 10, 29);

  group('ceilTo5', () {
    test('rounds up to the next five-minute mark', () {
      expect(ceilTo5(0), 0);
      expect(ceilTo5(1020), 1020);
      expect(ceilTo5(1021), 1025);
      expect(ceilTo5(1024), 1025);
      expect(ceilTo5(1025), 1025);
      expect(ceilTo5(1439), 1440);
      expect(ceilTo5(1440), 1440);
    });
  });

  group('buildDayPlan', () {
    test('clips today to the next five-minute boundary', () {
      final day = buildDayPlan(
        date: today,
        today: today,
        nowMinuteOfDay: 1142,
        windows: const [
          AvailabilityWindow(weekday: 4, startMinute: 1080, endMinute: 1260),
        ],
        lockedSessions: const [],
        settings: settings,
      );

      expect(day.freeIntervals, hasLength(1));
      expect(day.freeIntervals.single.startMinute, 1145);
      expect(day.freeIntervals.single.endMinute, 1260);
      expect(day.remainingCapacity, 120);
    });

    test('merges adjacent availability windows', () {
      final day = buildDayPlan(
        date: today.addDays(1),
        today: today,
        nowMinuteOfDay: 1020,
        windows: const [
          AvailabilityWindow(weekday: 5, startMinute: 1080, endMinute: 1170),
          AvailabilityWindow(weekday: 5, startMinute: 1170, endMinute: 1260),
        ],
        lockedSessions: const [],
        settings: settings,
      );

      expect(day.freeIntervals, hasLength(1));
      expect(day.freeIntervals.single.startMinute, 1080);
      expect(day.freeIntervals.single.endMinute, 1260);
      expect(day.freeIntervals.single.length, 180);
    });
  });

  test('Example A: feasible plan with gap filling', () {
    final result = generatePlan(
      _input(
        today: today,
        horizonDays: 14,
        availability: _windowsFor([4, 5]),
        tasks: [
          _task(
            'A',
            remainingMinutes: 120,
            priority: TaskPriority.high,
            deadline: LocalDate(2026, 10, 30),
          ),
          _task('B', remainingMinutes: 60),
        ],
      ),
    );

    expect(_descriptions(result), [
      '2026-10-29 1080 50 A',
      '2026-10-29 1140 50 A',
      '2026-10-29 1200 20 A',
      '2026-10-30 1080 50 B',
      '2026-10-30 1140 10 B',
    ]);
    expect(_allocation(result, 'A').newlyPlannedMinutes, 120);
    expect(_allocation(result, 'A').unscheduledMinutes, 0);
    expect(_allocation(result, 'B').newlyPlannedMinutes, 60);
    expect(_allocation(result, 'B').unscheduledMinutes, 0);
    expect(result.daySummaries[0].plannedMinutes, 120);
    expect(result.daySummaries[0].remainingCapacity, 0);
    expect(result.daySummaries[1].plannedMinutes, 60);
    expect(result.daySummaries[1].remainingCapacity, 60);
    expect(result.issues, isEmpty);
  });

  test('Example B: hard deadline caps placement and leaves a remainder', () {
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
    for (final session in result.sessions) {
      expect(session.date.isAfter(friday), isFalse);
    }
    expect(_allocation(result, 'A').newlyPlannedMinutes, 240);
    expect(_allocation(result, 'A').unscheduledMinutes, 60);
    expect(result.issues, isEmpty);
  });

  test('splits a long task across days by the daily limit', () {
    final result = generatePlan(
      _input(
        today: LocalDate(2026, 11, 2),
        horizonDays: 2,
        availability: _windowsFor([1, 2, 3, 4, 5]),
        tasks: [_task('long', remainingMinutes: 200)],
      ),
    );

    expect(_descriptions(result), [
      '2026-11-02 1080 50 long',
      '2026-11-02 1140 50 long',
      '2026-11-02 1200 20 long',
      '2026-11-03 1080 50 long',
      '2026-11-03 1140 30 long',
    ]);
    expect(_allocation(result, 'long').newlyPlannedMinutes, 200);
    expect(_allocation(result, 'long').unscheduledMinutes, 0);
    expect(result.daySummaries[0].plannedMinutes, 120);
    expect(result.daySummaries[0].remainingCapacity, 0);
    expect(result.daySummaries[1].plannedMinutes, 80);
    expect(result.daySummaries[1].remainingCapacity, 40);
  });

  test('allows a final short remainder below the session minimum', () {
    final result = generatePlan(
      _input(
        today: LocalDate(2026, 11, 2),
        horizonDays: 1,
        availability: _windowsFor([1]),
        tasks: [_task('short', remainingMinutes: 10)],
      ),
    );

    expect(_descriptions(result), ['2026-11-02 1080 10 short']);
    expect(_allocation(result, 'short').newlyPlannedMinutes, 10);
    expect(_allocation(result, 'short').unscheduledMinutes, 0);
  });

  test('avoids completed locked time using planned or actual minutes', () {
    final result = generatePlan(
      _input(
        today: LocalDate(2026, 11, 2),
        horizonDays: 1,
        availability: _windowsFor([1]),
        tasks: [_task('new', remainingMinutes: 80)],
        lockedSessions: [
          LockedSession(
            taskId: 'old',
            date: LocalDate(2026, 11, 2),
            startMinute: 1080,
            plannedMinutes: 50,
            status: SessionStatus.completed,
            actualMinutes: 70,
          ),
        ],
      ),
    );

    expect(_descriptions(result), ['2026-11-02 1160 50 new']);
    expect(_allocation(result, 'new').newlyPlannedMinutes, 50);
    expect(_allocation(result, 'new').unscheduledMinutes, 30);
    expect(result.daySummaries.single.plannedMinutes, 50);
    expect(result.daySummaries.single.remainingCapacity, 0);
  });

  test('reserves active session minutes for its task', () {
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
            status: SessionStatus.activeScheduledToday,
          ),
        ],
      ),
    );

    expect(_descriptions(result), ['2026-11-02 1140 10 A']);
    final allocation = _allocation(result, 'A');
    expect(allocation.reservedActiveMinutes, 50);
    expect(allocation.newlyPlannedMinutes, 10);
    expect(allocation.unscheduledMinutes, 0);
    expect(result.daySummaries.single.plannedMinutes, 10);
    expect(result.daySummaries.single.remainingCapacity, 60);
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

TaskAllocation _allocation(PlanResult result, String taskId) {
  return result.allocations.firstWhere(
    (allocation) => allocation.taskId == taskId,
  );
}
