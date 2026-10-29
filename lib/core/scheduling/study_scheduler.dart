import 'dart:math';

import '../time/local_date.dart';
import 'scheduling_models.dart';
import 'task_ordering.dart';

int ceilTo5(int nowMinute) {
  final remainder = nowMinute % 5;
  if (remainder == 0) {
    return nowMinute;
  }
  return nowMinute + 5 - remainder;
}

class FreeInterval {
  const FreeInterval(this.startMinute, this.endMinute);

  final int startMinute;
  final int endMinute;

  int get length => endMinute - startMinute;
}

class DayPlan {
  DayPlan(this.date, List<FreeInterval> freeIntervals, this.remainingCapacity)
    : freeIntervals = List<FreeInterval>.of(freeIntervals);

  final LocalDate date;
  final List<FreeInterval> freeIntervals;
  int remainingCapacity;
}

DayPlan buildDayPlan({
  required LocalDate date,
  required LocalDate today,
  required int nowMinuteOfDay,
  required List<AvailabilityWindow> windows,
  required List<LockedSession> lockedSessions,
  required SchedulingSettings settings,
}) {
  final mergedWindows = _mergeWindows(
    windows.where((window) => window.weekday == date.weekday).toList(),
  );
  final dayLocks = lockedSessions
      .where((session) => session.date.isSameDay(date))
      .toList();
  final consumedMinutes = dayLocks.fold<int>(
    0,
    (total, session) => total + _consumedMinutes(session),
  );
  final remainingCapacity = max(
    0,
    settings.dailyLimitMinutes - consumedMinutes,
  );
  final earliestMinute = date.isSameDay(today) ? ceilTo5(nowMinuteOfDay) : 0;
  final freeIntervals = <FreeInterval>[];

  for (final window in mergedWindows) {
    final windowStart = max(window.startMinute, earliestMinute);
    if (windowStart >= window.endMinute) {
      continue;
    }
    final blocked = <FreeInterval>[];
    for (final lock in dayLocks) {
      final occupiedDuration = _occupiedMinutes(lock);
      final occupiedEnd = min(1440, lock.startMinute + occupiedDuration);
      final blockStart = max(windowStart, lock.startMinute);
      final blockEnd = min(window.endMinute, occupiedEnd);
      if (blockEnd > blockStart) {
        blocked.add(FreeInterval(blockStart, blockEnd));
      }

      if (occupiedEnd > windowStart) {
        final breakStart = max(windowStart, occupiedEnd);
        final breakEnd = min(
          window.endMinute,
          occupiedEnd + settings.breakMinutes,
        );
        if (breakEnd > breakStart) {
          blocked.add(FreeInterval(breakStart, breakEnd));
        }
      }
    }

    final mergedBlocks = _mergeIntervals(blocked);
    var cursor = windowStart;
    for (final block in mergedBlocks) {
      if (block.startMinute > cursor) {
        freeIntervals.add(FreeInterval(cursor, block.startMinute));
      }
      if (block.endMinute > cursor) {
        cursor = block.endMinute;
      }
    }
    if (cursor < window.endMinute) {
      freeIntervals.add(FreeInterval(cursor, window.endMinute));
    }
  }

  return DayPlan(date, freeIntervals, remainingCapacity);
}

PlanResult generatePlan(SchedulingInput input) {
  final today = input.today;
  final settings = input.settings;
  final horizonEnd = today.addDays(input.horizonDays - 1);
  final days = <LocalDate, DayPlan>{};

  for (var offset = 0; offset < input.horizonDays; offset++) {
    final date = today.addDays(offset);
    final windows = input.availability
        .where((window) => window.weekday == date.weekday)
        .toList();
    days[date] = buildDayPlan(
      date: date,
      today: today,
      nowMinuteOfDay: input.nowMinuteOfDay,
      windows: windows,
      lockedSessions: input.lockedSessions,
      settings: settings,
    );
  }

  final sessions = <PlannedSession>[];
  final allocations = <TaskAllocation>[];
  final plannedByDate = <LocalDate, int>{};

  for (final task in sortTasks(input.tasks, today)) {
    final reservedMinutes = _reservedActiveMinutes(
      task.id,
      input.lockedSessions,
    );
    var remaining = max(0, task.remainingMinutes - reservedMinutes);
    var newlyPlanned = 0;

    final mode = _modeFor(task, today, horizonEnd);
    final searchEndDay = mode == SchedulingMode.hardDeadline
        ? task.deadline!
        : horizonEnd;
    final notBefore = task.notBefore;
    final searchStartDay = notBefore != null && notBefore.isAfter(today)
        ? notBefore
        : today;

    if (!searchStartDay.isAfter(searchEndDay)) {
      while (remaining > 0) {
        var placed = false;
        for (
          var date = searchStartDay;
          !date.isAfter(searchEndDay);
          date = date.addDays(1)
        ) {
          final day = days[date];
          if (day == null || day.remainingCapacity <= 0) {
            continue;
          }
          for (var index = 0; index < day.freeIntervals.length; index++) {
            if (day.remainingCapacity <= 0) {
              break;
            }
            final interval = day.freeIntervals[index];
            final desired = min(settings.blockLengthMinutes, remaining);
            final available = min(interval.length, day.remainingCapacity);
            final size = min(desired, available);
            if (size <= 0) {
              continue;
            }
            if (size < settings.minSessionMinutes && remaining > size) {
              continue;
            }

            sessions.add(
              PlannedSession(
                taskId: task.id,
                date: date,
                startMinute: interval.startMinute,
                plannedMinutes: size,
              ),
            );
            remaining -= size;
            newlyPlanned += size;
            day.remainingCapacity -= size;
            plannedByDate.update(
              date,
              (minutes) => minutes + size,
              ifAbsent: () => size,
            );

            final nextStart =
                interval.startMinute + size + settings.breakMinutes;
            if (nextStart < interval.endMinute) {
              day.freeIntervals[index] = FreeInterval(
                nextStart,
                interval.endMinute,
              );
            } else {
              day.freeIntervals.removeAt(index);
            }
            placed = true;
            break;
          }
          if (placed) {
            break;
          }
        }
        if (!placed) {
          break;
        }
      }
    }

    allocations.add(
      TaskAllocation(
        taskId: task.id,
        newlyPlannedMinutes: newlyPlanned,
        reservedActiveMinutes: reservedMinutes,
        unscheduledMinutes: remaining,
      ),
    );
  }

  sessions.sort((a, b) {
    final byDate = a.date.compareTo(b.date);
    if (byDate != 0) {
      return byDate;
    }
    final byStart = a.startMinute.compareTo(b.startMinute);
    if (byStart != 0) {
      return byStart;
    }
    return a.taskId.compareTo(b.taskId);
  });

  final daySummaries = <DaySummary>[
    for (var offset = 0; offset < input.horizonDays; offset++)
      _daySummary(
        today.addDays(offset),
        days[today.addDays(offset)]!,
        plannedByDate[today.addDays(offset)] ?? 0,
      ),
  ];

  return PlanResult(
    sessions: sessions,
    allocations: allocations,
    daySummaries: daySummaries,
    issues: const [],
  );
}

DaySummary _daySummary(LocalDate date, DayPlan day, int plannedMinutes) {
  return DaySummary(
    date: date,
    plannedMinutes: plannedMinutes,
    remainingCapacity: day.remainingCapacity,
  );
}

SchedulingMode _modeFor(
  EngineTask task,
  LocalDate today,
  LocalDate horizonEnd,
) {
  final deadline = task.deadline;
  if (deadline == null) {
    return SchedulingMode.noDeadline;
  }
  if (deadline.isBefore(today)) {
    return SchedulingMode.overdue;
  }
  if (!deadline.isAfter(horizonEnd)) {
    return SchedulingMode.hardDeadline;
  }
  return SchedulingMode.farDeadline;
}

int _reservedActiveMinutes(String taskId, List<LockedSession> lockedSessions) {
  var total = 0;
  for (final session in lockedSessions) {
    if (session.taskId != taskId) {
      continue;
    }
    if (session.status == SessionStatus.inProgress ||
        session.status == SessionStatus.activeScheduledToday) {
      total += session.plannedMinutes;
    }
  }
  return total;
}

int _occupiedMinutes(LockedSession session) {
  return switch (session.status) {
    SessionStatus.completed => max(
      session.plannedMinutes,
      session.actualMinutes ?? session.plannedMinutes,
    ),
    SessionStatus.inProgress => max(
      session.plannedMinutes,
      session.elapsedMinutes ?? 0,
    ),
    SessionStatus.activeScheduledToday => session.plannedMinutes,
  };
}

int _consumedMinutes(LockedSession session) {
  return switch (session.status) {
    SessionStatus.completed => session.actualMinutes ?? session.plannedMinutes,
    SessionStatus.inProgress => max(
      session.plannedMinutes,
      session.elapsedMinutes ?? 0,
    ),
    SessionStatus.activeScheduledToday => session.plannedMinutes,
  };
}

List<AvailabilityWindow> _mergeWindows(List<AvailabilityWindow> windows) {
  if (windows.isEmpty) {
    return const [];
  }
  final sorted = [...windows]
    ..sort((a, b) => a.startMinute.compareTo(b.startMinute));
  final merged = <AvailabilityWindow>[sorted.first];
  for (var index = 1; index < sorted.length; index++) {
    final next = sorted[index];
    final last = merged.last;
    if (next.startMinute <= last.endMinute) {
      merged[merged.length - 1] = AvailabilityWindow(
        weekday: last.weekday,
        startMinute: last.startMinute,
        endMinute: max(last.endMinute, next.endMinute),
      );
    } else {
      merged.add(next);
    }
  }
  return merged;
}

List<FreeInterval> _mergeIntervals(List<FreeInterval> intervals) {
  if (intervals.isEmpty) {
    return const [];
  }
  final sorted = [...intervals]
    ..sort((a, b) => a.startMinute.compareTo(b.startMinute));
  final merged = <FreeInterval>[sorted.first];
  for (var index = 1; index < sorted.length; index++) {
    final next = sorted[index];
    final last = merged.last;
    if (next.startMinute <= last.endMinute) {
      if (next.endMinute > last.endMinute) {
        merged[merged.length - 1] = FreeInterval(
          last.startMinute,
          next.endMinute,
        );
      }
    } else {
      merged.add(next);
    }
  }
  return merged;
}
