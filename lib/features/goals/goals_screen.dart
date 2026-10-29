import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'goal_colors.dart';
import 'providers/goals_providers.dart';

class GoalsScreen extends ConsumerWidget {
  const GoalsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final goalsAsync = ref.watch(goalsProvider);
    return Scaffold(
      body: goalsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'Could not load goals.\n$error',
              textAlign: TextAlign.center,
            ),
          ),
        ),
        data: (goals) {
          if (goals.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'No goals yet. Create one to get started!',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            itemCount: goals.length,
            separatorBuilder: (context, index) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final goal = goals[index];
              final description = goal.description?.trim();
              return Card(
                child: ListTile(
                  leading: _GoalColorDot(colorIndex: goal.colorIndex),
                  title: Text(goal.title),
                  subtitle: description == null || description.isEmpty
                      ? null
                      : Text(description),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: 'New goal',
        onPressed: () => context.push('/goals/new'),
        child: const Icon(Icons.add),
      ),
    );
  }
}

class _GoalColorDot extends StatelessWidget {
  const _GoalColorDot({required this.colorIndex});

  final int colorIndex;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 16,
      height: 16,
      decoration: BoxDecoration(
        color: goalColorForIndex(colorIndex),
        shape: BoxShape.circle,
      ),
    );
  }
}
