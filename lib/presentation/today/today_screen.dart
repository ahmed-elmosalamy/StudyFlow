import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../data/database/app_database.dart';
import '../../../data/database/tables.dart';
import '../../features/today/providers/today_providers.dart';

class TodayScreen extends ConsumerWidget {
  const TodayScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessionsAsync = ref.watch(todaySessionsProvider);
    final tasks = ref.watch(todayTasksProvider).value ?? const <Task>[];
    return sessionsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            "Could not load today's sessions.\n$error",
            textAlign: TextAlign.center,
          ),
        ),
      ),
      data: (sessions) => sessions.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'No study sessions planned for today. Enjoy your free time!',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : _SessionList(sessions: sessions, tasks: tasks),
    );
  }
}

class _SessionList extends StatelessWidget {
  const _SessionList({required this.sessions, required this.tasks});

  final List<StudySession> sessions;
  final List<Task> tasks;

  @override
  Widget build(BuildContext context) {
    final tasksById = {for (final task in tasks) task.id: task};
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      itemCount: sessions.length,
      itemBuilder: (context, index) {
        final session = sessions[index];
        final inProgress = session.status == SessionStatus.in_progress;
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            onTap: () => context.push('/focus/${session.id}'),
            leading: Icon(
              inProgress ? Icons.play_circle_outline : Icons.menu_book_outlined,
            ),
            title: Text(tasksById[session.taskId]?.title ?? 'Task'),
            subtitle: Text(
              '${_formatMinute(session.startMinute)} - '
              '${_formatMinute(session.startMinute + session.plannedMinutes)}'
              ' | ${session.plannedMinutes} min',
            ),
            trailing: inProgress
                ? Text(
                    'In progress',
                    style: Theme.of(context).textTheme.labelSmall,
                  )
                : null,
          ),
        );
      },
    );
  }
}

class TodayReplanAction extends ConsumerStatefulWidget {
  const TodayReplanAction({super.key});

  @override
  ConsumerState<TodayReplanAction> createState() => _TodayReplanActionState();
}

class _TodayReplanActionState extends ConsumerState<TodayReplanAction> {
  var _replanning = false;

  Future<void> _replan() async {
    if (_replanning) {
      return;
    }
    setState(() => _replanning = true);
    try {
      final result = await ref.read(planServiceProvider).replan();
      if (!mounted) {
        return;
      }
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
        setState(() => _replanning = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      key: const ValueKey('today-replan-button'),
      onPressed: _replanning ? null : _replan,
      icon: _replanning
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.refresh),
      label: const Text('Replan'),
    );
  }
}

String _formatMinute(int minute) {
  final hours = (minute ~/ 60).toString().padLeft(2, '0');
  final minutes = (minute % 60).toString().padLeft(2, '0');
  return '$hours:$minutes';
}
