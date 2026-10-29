import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../data/database/app_database.dart';
import '../../../data/repositories/session_repository.dart';
import '../../tasks/providers/tasks_providers.dart';

final todaySessionsProvider = StreamProvider.autoDispose<List<StudySession>>((
  ref,
) {
  final repository = SessionRepository(ref.watch(databaseProvider));
  final today = ref.watch(clockProvider).today.toString();
  return repository.watchTodaySessions(today);
});

final todayTasksProvider = StreamProvider.autoDispose<List<Task>>((ref) {
  return ref.watch(taskRepositoryProvider).watchAll();
});
