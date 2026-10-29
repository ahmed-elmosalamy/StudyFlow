import '../time/local_date.dart';

enum TaskKind { study, revision }

enum TaskPriority { low, normal, high }

enum SchedulingMode { hardDeadline, farDeadline, overdue, noDeadline, deferred }

enum SessionStatus { completed, inProgress, activeScheduledToday }

class SchedulingSettings {
  const SchedulingSettings({
    required this.dailyLimitMinutes,
    required this.blockLengthMinutes,
    required this.minSessionMinutes,
    required this.breakMinutes,
  });

  final int dailyLimitMinutes;
  final int blockLengthMinutes;
  final int minSessionMinutes;
  final int breakMinutes;
}

class AvailabilityWindow {
  const AvailabilityWindow({
    required this.weekday,
    required this.startMinute,
    required this.endMinute,
  });

  final int weekday;
  final int startMinute;
  final int endMinute;
}

class SchedulingInput {
  const SchedulingInput({
    required this.today,
    required this.nowMinuteOfDay,
    required this.horizonDays,
    required this.settings,
    required this.availability,
    required this.tasks,
    required this.lockedSessions,
  });

  final LocalDate today;
  final int nowMinuteOfDay;
  final int horizonDays;
  final SchedulingSettings settings;
  final List<AvailabilityWindow> availability;
  final List<EngineTask> tasks;
  final List<LockedSession> lockedSessions;
}

class EngineTask {
  const EngineTask({
    required this.id,
    required this.kind,
    required this.priority,
    required this.remainingMinutes,
    required this.deadline,
    required this.notBefore,
    required this.createdAt,
  });

  final String id;
  final TaskKind kind;
  final TaskPriority priority;
  final int remainingMinutes;
  final LocalDate? deadline;
  final LocalDate? notBefore;
  final int createdAt;
}

class LockedSession {
  const LockedSession({
    required this.taskId,
    required this.date,
    required this.startMinute,
    required this.plannedMinutes,
    required this.status,
    this.actualMinutes,
    this.elapsedMinutes,
  });

  final String taskId;
  final LocalDate date;
  final int startMinute;
  final int plannedMinutes;
  final SessionStatus status;
  final int? actualMinutes;
  final int? elapsedMinutes;
}

class PlannedSession {
  const PlannedSession({
    required this.taskId,
    required this.date,
    required this.startMinute,
    required this.plannedMinutes,
  });

  final String taskId;
  final LocalDate date;
  final int startMinute;
  final int plannedMinutes;
}

class TaskAllocation {
  const TaskAllocation({
    required this.taskId,
    required this.newlyPlannedMinutes,
    required this.reservedActiveMinutes,
    required this.unscheduledMinutes,
  });

  final String taskId;
  final int newlyPlannedMinutes;
  final int reservedActiveMinutes;
  final int unscheduledMinutes;
}

class DaySummary {
  const DaySummary({
    required this.date,
    required this.plannedMinutes,
    required this.remainingCapacity,
  });

  final LocalDate date;
  final int plannedMinutes;
  final int remainingCapacity;
}

class PlanResult {
  const PlanResult({
    required this.sessions,
    required this.allocations,
    required this.daySummaries,
    required this.issues,
  });

  final List<PlannedSession> sessions;
  final List<TaskAllocation> allocations;
  final List<DaySummary> daySummaries;
  final List<SchedulingIssue> issues;
}

enum SchedulingIssueType {
  noAvailability,
  impossibleDeadline,
  overdueTask,
  horizonBacklog,
  beyondHorizon,
  deferredBeyondHorizon,
}

class SchedulingIssue {
  const SchedulingIssue({
    required this.type,
    this.taskId,
    this.deadline,
    this.notBefore,
    this.remainingMinutes,
    this.reservedActiveMinutes,
    this.scheduledBeforeDeadlineMinutes,
    this.deficitMinutes,
    this.availableCapacityBeforeDeadline,
    this.otherMinutesBeforeDeadline,
    this.daysAvailableBeforeDeadline,
    this.suggestedExtraMinutesPerDay,
    this.scheduledMinutes,
    this.unscheduledMinutes,
    this.daysOverdue,
  });

  final SchedulingIssueType type;
  final String? taskId;
  final LocalDate? deadline;
  final LocalDate? notBefore;
  final int? remainingMinutes;
  final int? reservedActiveMinutes;
  final int? scheduledBeforeDeadlineMinutes;
  final int? deficitMinutes;
  final int? availableCapacityBeforeDeadline;
  final int? otherMinutesBeforeDeadline;
  final int? daysAvailableBeforeDeadline;
  final int? suggestedExtraMinutesPerDay;
  final int? scheduledMinutes;
  final int? unscheduledMinutes;
  final int? daysOverdue;
}
