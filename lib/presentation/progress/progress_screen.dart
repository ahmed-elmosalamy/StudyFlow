import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database/app_database.dart';
import '../../features/progress/providers/progress_providers.dart';

class ProgressScreen extends ConsumerWidget {
  const ProgressScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progressAsync = ref.watch(progressProvider);
    return progressAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Could not load progress.\n$error',
            textAlign: TextAlign.center,
          ),
        ),
      ),
      data: (snapshot) {
        final recent =
            ref.watch(recentCompletedSessionsProvider).value ??
            const <StudySession>[];
        final tasks = ref.watch(progressTasksProvider).value ?? const <Task>[];
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            _SummaryCard(snapshot: snapshot),
            const SizedBox(height: 16),
            _WeeklyChart(dailyMinutes: snapshot.dailyMinutes),
            const SizedBox(height: 16),
            _RecentSessions(sessions: recent, tasks: tasks),
          ],
        );
      },
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.snapshot});

  final ProgressSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(
              child: _SummaryValue(
                label: 'Total Study Time',
                value: _formatMinutes(snapshot.totalMinutesThisWeek),
                valueKey: const ValueKey('progress-total'),
              ),
            ),
            const SizedBox(
              height: 48,
              child: VerticalDivider(width: 1, thickness: 1),
            ),
            Expanded(
              child: _SummaryValue(
                label: 'Sessions Completed',
                value: '${snapshot.completedSessionsCount}',
                valueKey: const ValueKey('progress-sessions-count'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryValue extends StatelessWidget {
  const _SummaryValue({
    required this.label,
    required this.value,
    required this.valueKey,
  });

  final String label;
  final String value;
  final Key valueKey;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Text(
          label,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 4),
        Text(
          value,
          key: valueKey,
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _WeeklyChart extends StatelessWidget {
  const _WeeklyChart({required this.dailyMinutes});

  static const _labels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
  static const _chartHeight = 120.0;

  final List<DailyStudyMinutes> dailyMinutes;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final maxMinutes = dailyMinutes.fold(
      0,
      (max, day) => math.max(max, day.minutes),
    );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('This Week', style: theme.textTheme.titleMedium),
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var index = 0; index < dailyMinutes.length; index++)
                  Expanded(
                    child: _DayBar(
                      label: _labels[index],
                      day: dailyMinutes[index],
                      maxMinutes: maxMinutes,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DayBar extends StatelessWidget {
  const _DayBar({
    required this.label,
    required this.day,
    required this.maxMinutes,
  });

  final String label;
  final DailyStudyMinutes day;
  final int maxMinutes;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final barHeight = maxMinutes == 0 || day.minutes == 0
        ? 0.0
        : math.max(4.0, day.minutes / maxMinutes * _WeeklyChart._chartHeight);
    return Semantics(
      label: '${day.date}: ${day.minutes} minutes',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: _WeeklyChart._chartHeight,
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Container(
                key: ValueKey('progress-bar-${day.date}'),
                height: barHeight,
                width: 20,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(4),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(label, style: theme.textTheme.labelSmall),
        ],
      ),
    );
  }
}

class _RecentSessions extends StatelessWidget {
  const _RecentSessions({required this.sessions, required this.tasks});

  final List<StudySession> sessions;
  final List<Task> tasks;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tasksById = {for (final task in tasks) task.id: task};
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Text(
                'Recently Completed',
                style: theme.textTheme.titleMedium,
              ),
            ),
            if (sessions.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('No completed sessions yet.'),
              )
            else
              for (final session in sessions)
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.check_circle_outline),
                  title: Text(tasksById[session.taskId]?.title ?? 'Task'),
                  subtitle: Text(
                    '${session.sessionDate} | ${session.actualMinutes ?? 0} min',
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

String _formatMinutes(int minutes) {
  final hours = minutes ~/ 60;
  final remainder = minutes % 60;
  if (hours == 0) {
    return '${remainder}m';
  }
  return '${hours}h ${remainder}m';
}
