import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../data/database/app_database.dart';
import '../../subjects/providers/subjects_providers.dart';
import '../providers/goals_providers.dart';

class GoalDetailScreen extends ConsumerWidget {
  const GoalDetailScreen({super.key, required this.goalId});

  final String goalId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final goalsAsync = ref.watch(goalsProvider);
    final goal = _findGoal(goalsAsync.value ?? const <Goal>[], goalId);

    return Scaffold(
      appBar: AppBar(title: Text(goal?.title ?? 'Goal')),
      body: goalsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => _Message('Could not load goal.\n$error'),
        data: (goals) {
          if (_findGoal(goals, goalId) == null) {
            return const _Message('Goal not found.');
          }
          final subjectsAsync = ref.watch(subjectsForGoalProvider(goalId));
          return subjectsAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => _Message('Could not load subjects.\n$error'),
            data: (subjects) {
              if (subjects.isEmpty) {
                return const _Message(
                  'No subjects yet. Add one to get started!',
                );
              }
              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                itemCount: subjects.length,
                separatorBuilder: (context, index) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final subject = subjects[index];
                  final notes = subject.notes?.trim();
                  return Card(
                    child: ListTile(
                      title: Text(subject.title),
                      subtitle: notes == null || notes.isEmpty
                          ? null
                          : Text(notes),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () =>
                          context.push('/goals/$goalId/subjects/${subject.id}'),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
      floatingActionButton: goal == null
          ? null
          : FloatingActionButton(
              tooltip: 'New subject',
              onPressed: () => context.push('/goals/$goalId/subjects/new'),
              child: const Icon(Icons.add),
            ),
    );
  }
}

Goal? _findGoal(List<Goal> goals, String goalId) {
  for (final goal in goals) {
    if (goal.id == goalId) {
      return goal;
    }
  }
  return null;
}

class _Message extends StatelessWidget {
  const _Message(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(text, textAlign: TextAlign.center),
      ),
    );
  }
}
