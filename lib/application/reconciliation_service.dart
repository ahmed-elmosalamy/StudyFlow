import '../core/time/clock.dart';
import '../core/time/local_date.dart';
import '../data/repositories/session_repository.dart';
import '../data/repositories/settings_repository.dart';
import 'plan_service.dart';

class ReconciliationService {
  ReconciliationService({
    required this.sessionRepository,
    required this.settingsRepository,
    required this.planService,
    required this.clock,
  });

  final SessionRepository sessionRepository;
  final SettingsRepository settingsRepository;
  final PlanService planService;
  final Clock clock;

  Future<void> reconcile() async {
    final today = clock.today;
    final nowMinute = clock.nowMinuteOfDay;
    final scheduled = await sessionRepository.getScheduled();

    final missedIds = <String>[];
    for (final session in scheduled) {
      final date = LocalDate.parse(session.sessionDate);
      final endedToday =
          date.isSameDay(today) &&
          session.startMinute + session.plannedMinutes <= nowMinute;
      if (date.isBefore(today) || endedToday) {
        missedIds.add(session.id);
      }
    }

    if (missedIds.isEmpty) {
      return;
    }

    await sessionRepository.markMissed(
      missedIds,
      updatedAt: clock.now.millisecondsSinceEpoch,
    );

    final settings = await settingsRepository.getSettings();
    if (settings.autoReplan != 0) {
      await planService.replan();
    }
  }
}
