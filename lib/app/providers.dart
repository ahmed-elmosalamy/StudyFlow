import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/plan_service.dart';
import '../application/reconciliation_service.dart';
import '../core/time/clock.dart';
import '../data/database/app_database.dart';
import '../data/repositories/availability_repository.dart';
import '../data/repositories/goal_repository.dart';
import '../data/repositories/session_repository.dart';
import '../data/repositories/settings_repository.dart';
import '../data/repositories/task_repository.dart';

final databaseProvider = Provider<AppDatabase>((ref) {
  final database = AppDatabase();
  ref.onDispose(database.close);
  return database;
});

final clockProvider = Provider<Clock>((ref) => const SystemClock());

final goalRepositoryProvider = Provider<GoalRepository>((ref) {
  return GoalRepository(ref.watch(databaseProvider));
});

final planServiceProvider = Provider<PlanService>((ref) {
  final database = ref.watch(databaseProvider);
  return PlanService(
    database: database,
    taskRepository: TaskRepository(database),
    sessionRepository: SessionRepository(database),
    settingsRepository: SettingsRepository(database),
    availabilityRepository: AvailabilityRepository(database),
    clock: ref.watch(clockProvider),
  );
});

final reconciliationServiceProvider = Provider<ReconciliationService>((ref) {
  final database = ref.watch(databaseProvider);
  return ReconciliationService(
    sessionRepository: SessionRepository(database),
    settingsRepository: SettingsRepository(database),
    planService: ref.watch(planServiceProvider),
    clock: ref.watch(clockProvider),
  );
});
