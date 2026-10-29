import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../data/database/app_database.dart';
import '../../../data/repositories/topic_repository.dart';

final topicRepositoryProvider = Provider<TopicRepository>((ref) {
  return TopicRepository(ref.watch(databaseProvider));
});

final topicsForSubjectProvider = StreamProvider.autoDispose
    .family<List<Topic>, String>((ref, subjectId) {
      return ref
          .watch(topicRepositoryProvider)
          .watchAll()
          .map(
            (topics) => topics
                .where((topic) => topic.subjectId == subjectId)
                .toList(growable: false),
          );
    });
