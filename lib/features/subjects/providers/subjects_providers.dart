import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../data/database/app_database.dart';
import '../../../data/repositories/subject_repository.dart';

final subjectRepositoryProvider = Provider<SubjectRepository>((ref) {
  return SubjectRepository(ref.watch(databaseProvider));
});

final subjectsForGoalProvider = StreamProvider.autoDispose
    .family<List<Subject>, String>((ref, goalId) {
      return ref
          .watch(subjectRepositoryProvider)
          .watchAll()
          .map(
            (subjects) => subjects
                .where((subject) => subject.goalId == goalId)
                .toList(growable: false),
          );
    });
