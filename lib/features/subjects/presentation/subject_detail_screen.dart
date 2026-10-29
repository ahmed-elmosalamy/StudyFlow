import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../data/database/app_database.dart';
import '../../../data/database/tables.dart';
import '../../topics/providers/topics_providers.dart';
import '../providers/subjects_providers.dart';

class SubjectDetailScreen extends ConsumerWidget {
  const SubjectDetailScreen({
    super.key,
    required this.goalId,
    required this.subjectId,
  });

  final String goalId;
  final String subjectId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final subjectsAsync = ref.watch(subjectsForGoalProvider(goalId));
    final subject = _findSubject(
      subjectsAsync.value ?? const <Subject>[],
      subjectId,
    );

    return Scaffold(
      appBar: AppBar(title: Text(subject?.title ?? 'Subject')),
      body: subjectsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => _Message('Could not load subject.\n$error'),
        data: (subjects) {
          if (_findSubject(subjects, subjectId) == null) {
            return const _Message('Subject not found.');
          }
          final topicsAsync = ref.watch(topicsForSubjectProvider(subjectId));
          return topicsAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => _Message('Could not load topics.\n$error'),
            data: (topics) {
              if (topics.isEmpty) {
                return const _Message('No topics yet. Add one to get started!');
              }
              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                itemCount: topics.length,
                separatorBuilder: (context, index) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final topic = topics[index];
                  final notes = topic.notes?.trim();
                  return Card(
                    child: ListTile(
                      title: Text(topic.title),
                      subtitle: notes == null || notes.isEmpty
                          ? null
                          : Text(notes),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _topicStatusLabel(topic.status),
                            style: Theme.of(context).textTheme.labelMedium,
                          ),
                          const SizedBox(width: 4),
                          const Icon(Icons.chevron_right),
                        ],
                      ),
                      onTap: () => context.push(
                        '/goals/$goalId/subjects/$subjectId/topics/${topic.id}',
                      ),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
      floatingActionButton: subject == null
          ? null
          : FloatingActionButton(
              tooltip: 'New topic',
              onPressed: () =>
                  context.push('/goals/$goalId/subjects/$subjectId/topics/new'),
              child: const Icon(Icons.add),
            ),
    );
  }
}

Subject? _findSubject(List<Subject> subjects, String subjectId) {
  for (final subject in subjects) {
    if (subject.id == subjectId) {
      return subject;
    }
  }
  return null;
}

String _topicStatusLabel(TopicStatus status) {
  return switch (status) {
    TopicStatus.not_started => 'Not started',
    TopicStatus.learning => 'Learning',
    TopicStatus.learned => 'Learned',
    TopicStatus.archived => 'Archived',
  };
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
