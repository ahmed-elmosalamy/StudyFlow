import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../data/database/app_database.dart';
import '../../../data/repositories/session_repository.dart';
import '../../tasks/providers/tasks_providers.dart';

class DailyStudyMinutes {
  const DailyStudyMinutes({required this.date, required this.minutes});

  final String date;
  final int minutes;
}

class ProgressSnapshot {
  const ProgressSnapshot({
    required this.totalMinutesThisWeek,
    required this.completedSessionsCount,
    required this.dailyMinutes,
  });

  final int totalMinutesThisWeek;
  final int completedSessionsCount;
  final List<DailyStudyMinutes> dailyMinutes;
}

final progressProvider = StreamProvider.autoDispose<ProgressSnapshot>((ref) {
  final repository = SessionRepository(ref.watch(databaseProvider));
  final today = ref.watch(clockProvider).today;
  final monday = today.addDays(1 - today.weekday);
  final sunday = monday.addDays(6);
  final days = [
    for (var offset = 0; offset < 7; offset++) monday.addDays(offset),
  ];

  return repository
      .watchCompletedBetween(
        fromDate: monday.toString(),
        toDate: sunday.toString(),
      )
      .map((sessions) {
        final minutesByDate = {for (final day in days) day.toString(): 0};
        var total = 0;
        for (final session in sessions) {
          final minutes = session.actualMinutes ?? 0;
          total += minutes;
          final date = session.sessionDate;
          if (minutesByDate.containsKey(date)) {
            minutesByDate[date] = minutesByDate[date]! + minutes;
          }
        }
        return ProgressSnapshot(
          totalMinutesThisWeek: total,
          completedSessionsCount: sessions.length,
          dailyMinutes: [
            for (final day in days)
              DailyStudyMinutes(
                date: day.toString(),
                minutes: minutesByDate[day.toString()]!,
              ),
          ],
        );
      });
});

final recentCompletedSessionsProvider =
    StreamProvider.autoDispose<List<StudySession>>((ref) {
      return SessionRepository(
        ref.watch(databaseProvider),
      ).watchRecentCompleted();
    });

final progressTasksProvider = StreamProvider.autoDispose<List<Task>>((ref) {
  return ref.watch(taskRepositoryProvider).watchAll();
});
