import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../data/database/app_database.dart';
import '../../../data/repositories/task_repository.dart';

final taskRepositoryProvider = Provider<TaskRepository>((ref) {
  return TaskRepository(ref.watch(databaseProvider));
});

final tasksForTopicProvider = StreamProvider.autoDispose
    .family<List<Task>, String>((ref, topicId) {
      return ref
          .watch(taskRepositoryProvider)
          .watchAll()
          .map(
            (tasks) => tasks
                .where((task) => task.topicId == topicId)
                .toList(growable: false),
          );
    });
