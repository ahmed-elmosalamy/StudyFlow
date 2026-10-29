import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../data/database/app_database.dart';
import '../../tasks/providers/tasks_providers.dart';
import '../providers/topics_providers.dart';

class TopicDetailScreen extends ConsumerWidget {
  const TopicDetailScreen({
    super.key,
    required this.goalId,
    required this.subjectId,
    required this.topicId,
  });

  final String goalId;
  final String subjectId;
  final String topicId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final topicsAsync = ref.watch(topicsForSubjectProvider(subjectId));
    final topic = _findTopic(topicsAsync.value ?? const <Topic>[], topicId);

    return Scaffold(
      appBar: AppBar(title: Text(topic?.title ?? 'Topic')),
      body: topicsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => _Message('Could not load topic.\n$error'),
        data: (topics) {
          if (_findTopic(topics, topicId) == null) {
            return const _Message('Topic not found.');
          }
          final tasksAsync = ref.watch(tasksForTopicProvider(topicId));
          return tasksAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => _Message('Could not load tasks.\n$error'),
            data: (tasks) {
              if (tasks.isEmpty) {
                return const _Message('No tasks yet. Add one to get started!');
              }
              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                itemCount: tasks.length,
                separatorBuilder: (context, index) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final task = tasks[index];
                  return Card(
                    child: ListTile(
                      leading: Icon(
                        _priorityIcon(task.priority),
                        semanticLabel:
                            '${_priorityLabel(task.priority)} priority',
                      ),
                      title: Text(task.title),
                      subtitle: Text(_taskSummary(task)),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
      floatingActionButton: topic == null
          ? null
          : FloatingActionButton(
              tooltip: 'New task',
              onPressed: () => context.push(
                '/goals/$goalId/subjects/$subjectId/topics/$topicId/tasks/new',
              ),
              child: const Icon(Icons.add),
            ),
    );
  }
}

Topic? _findTopic(List<Topic> topics, String topicId) {
  for (final topic in topics) {
    if (topic.id == topicId) {
      return topic;
    }
  }
  return null;
}

String _priorityLabel(int priority) {
  return switch (priority) {
    0 => 'Low',
    2 => 'High',
    _ => 'Normal',
  };
}

IconData _priorityIcon(int priority) {
  return switch (priority) {
    0 => Icons.low_priority,
    2 => Icons.priority_high,
    _ => Icons.drag_handle,
  };
}

String _taskSummary(Task task) {
  final deadline = task.deadlineDate == null
      ? 'No deadline'
      : 'Due ${task.deadlineDate}';
  return '${_priorityLabel(task.priority)} | '
      '${task.remainingMinutes} min left | $deadline';
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
