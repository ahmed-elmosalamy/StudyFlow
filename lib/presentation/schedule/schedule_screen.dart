import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/scheduling/scheduling_models.dart'
    show PlanResult, SchedulingIssue, SchedulingIssueType;
import '../../../data/database/app_database.dart';
import '../../features/schedule/providers/schedule_providers.dart';

const _weekdayNames = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

const _monthNames = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

class ScheduleScreen extends ConsumerStatefulWidget {
  const ScheduleScreen({super.key});

  @override
  ConsumerState<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends ConsumerState<ScheduleScreen> {
  var _generating = false;
  PlanResult? _lastPlan;

  Future<void> _generatePlan() async {
    if (_generating) {
      return;
    }
    setState(() => _generating = true);
    try {
      final result = await ref.read(planServiceProvider).replan();
      if (!mounted) {
        return;
      }
      setState(() => _lastPlan = result);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.sessions.isEmpty
                ? 'Plan generated with no sessions.'
                : 'Plan generated: ${result.sessions.length} sessions.',
          ),
        ),
      );
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not generate the plan.')),
      );
    } finally {
      if (mounted) {
        setState(() => _generating = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final sessionsAsync = ref.watch(scheduledSessionsProvider);
    final tasks = ref.watch(scheduleTasksProvider).value ?? const <Task>[];
    return Scaffold(
      body: Column(
        children: [
          if (_generating) const LinearProgressIndicator(),
          Expanded(
            child: sessionsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'Could not load the plan.\n$error',
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
              data: (sessions) => _buildSchedule(context, sessions, tasks),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: const ValueKey('generate-plan-button'),
        heroTag: 'generate-plan-fab',
        onPressed: _generating ? null : _generatePlan,
        icon: _generating
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.auto_awesome),
        label: const Text('Generate Plan'),
      ),
    );
  }

  Widget _buildSchedule(
    BuildContext context,
    List<StudySession> sessions,
    List<Task> tasks,
  ) {
    final tasksById = {for (final task in tasks) task.id: task};
    final issues = _lastPlan?.issues ?? const <SchedulingIssue>[];
    final items = <Widget>[];

    if (issues.isNotEmpty) {
      items.add(
        _WarningsCard(
          messages: [
            for (final issue in issues) _issueMessage(issue, tasksById),
          ],
        ),
      );
    }

    if (sessions.isEmpty) {
      items.add(
        const Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'No plan generated yet. Tap Generate Plan.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    } else {
      String? currentDate;
      for (final session in sessions) {
        if (session.sessionDate != currentDate) {
          currentDate = session.sessionDate;
          items.add(
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
              child: Text(
                _formatDate(session.sessionDate),
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
          );
        }
        items.add(
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              leading: const Icon(Icons.menu_book_outlined),
              title: Text(tasksById[session.taskId]?.title ?? 'Task'),
              subtitle: Text(
                '${_formatMinute(session.startMinute)} - '
                '${_formatMinute(session.startMinute + session.plannedMinutes)}'
                ' | ${session.plannedMinutes} min',
              ),
            ),
          ),
        );
      }
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      children: items,
    );
  }
}

class _WarningsCard extends StatelessWidget {
  const _WarningsCard({required this.messages});

  final List<String> messages;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Theme.of(context).colorScheme.errorContainer,
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Plan warnings',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            for (final message in messages)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(message),
              ),
          ],
        ),
      ),
    );
  }
}

String _issueMessage(SchedulingIssue issue, Map<String, Task> tasksById) {
  final taskId = issue.taskId;
  final title = taskId == null
      ? 'a task'
      : tasksById[taskId]?.title ?? 'a task';
  return switch (issue.type) {
    SchedulingIssueType.noAvailability =>
      'No availability windows are set for the planning horizon.',
    SchedulingIssueType.impossibleDeadline =>
      'Impossible deadline for $title: short by '
          '${issue.deficitMinutes ?? 0} minutes.',
    SchedulingIssueType.overdueTask =>
      'Overdue task $title: ${issue.unscheduledMinutes ?? 0} minutes remain '
          'unscheduled.',
    SchedulingIssueType.horizonBacklog =>
      'Not enough capacity for $title: ${issue.unscheduledMinutes ?? 0} '
          'minutes remain unscheduled.',
    SchedulingIssueType.beyondHorizon =>
      '$title extends beyond the planning horizon: '
          '${issue.unscheduledMinutes ?? 0} minutes remain unscheduled.',
    SchedulingIssueType.deferredBeyondHorizon =>
      '$title cannot start until ${issue.notBefore}.',
  };
}

String _formatDate(String value) {
  final date = DateTime.parse(value);
  return '${_weekdayNames[date.weekday - 1]}, '
      '${date.day} ${_monthNames[date.month - 1]}';
}

String _formatMinute(int minute) {
  final hours = (minute ~/ 60).toString().padLeft(2, '0');
  final minutes = (minute % 60).toString().padLeft(2, '0');
  return '$hours:$minutes';
}
