import '../time/local_date.dart';
import 'scheduling_models.dart';

List<EngineTask> sortTasks(List<EngineTask> tasks, LocalDate today) {
  final ordered = [...tasks];
  ordered.sort((a, b) => _compareTasks(a, b, today));
  return ordered;
}

int _compareTasks(EngineTask a, EngineTask b, LocalDate today) {
  final aDeadline = _effectiveDeadline(a.deadline, today);
  final bDeadline = _effectiveDeadline(b.deadline, today);

  if (aDeadline != null || bDeadline != null) {
    if (aDeadline == null) {
      return 1;
    }
    if (bDeadline == null) {
      return -1;
    }
    final byDeadline = aDeadline.compareTo(bDeadline);
    if (byDeadline != 0) {
      return byDeadline;
    }
    return _comparePriorityCreatedAtId(a, b);
  }

  final byKind = _kindRank(a.kind).compareTo(_kindRank(b.kind));
  if (byKind != 0) {
    return byKind;
  }
  return _comparePriorityCreatedAtId(a, b);
}

LocalDate? _effectiveDeadline(LocalDate? deadline, LocalDate today) {
  if (deadline == null) {
    return null;
  }
  return deadline.isBefore(today) ? today : deadline;
}

int _kindRank(TaskKind kind) {
  return switch (kind) {
    TaskKind.revision => 0,
    TaskKind.study => 1,
  };
}

int _comparePriorityCreatedAtId(EngineTask a, EngineTask b) {
  final byPriority = b.priority.index.compareTo(a.priority.index);
  if (byPriority != 0) {
    return byPriority;
  }
  final byCreatedAt = a.createdAt.compareTo(b.createdAt);
  if (byCreatedAt != 0) {
    return byCreatedAt;
  }
  return a.id.compareTo(b.id);
}
