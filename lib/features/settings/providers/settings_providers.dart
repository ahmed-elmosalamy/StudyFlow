import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../data/database/app_database.dart';
import '../../../data/repositories/availability_repository.dart';
import '../../../data/repositories/settings_repository.dart';

final settingsRepositoryProvider = Provider<SettingsRepository>((ref) {
  return SettingsRepository(ref.watch(databaseProvider));
});

final settingsProvider = StreamProvider.autoDispose<AppSetting>((ref) async* {
  final repository = ref.watch(settingsRepositoryProvider);
  await repository.getSettings();
  yield* repository
      .watchSettings()
      .where((settings) => settings != null)
      .cast<AppSetting>();
});

final availabilityRepositoryProvider = Provider<AvailabilityRepository>((ref) {
  return AvailabilityRepository(ref.watch(databaseProvider));
});

final availabilityProvider =
    StreamProvider.autoDispose<List<AvailabilityWindow>>((ref) {
      return ref.watch(availabilityRepositoryProvider).watchAll();
    });
