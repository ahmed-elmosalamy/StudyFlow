import 'package:drift/drift.dart';

import '../core/time/clock.dart';
import '../core/time/local_date.dart';
import '../core/validation.dart';
import '../data/database/tables.dart';
import '../data/repositories/settings_repository.dart';
import '../data/repositories/task_repository.dart';
import '../data/repositories/topic_repository.dart';

class RevisionService {
  RevisionService({
    required this.topicRepository,
    required this.taskRepository,
    required this.settingsRepository,
    required this.clock,
  });

  final TopicRepository topicRepository;
  final TaskRepository taskRepository;
  final SettingsRepository settingsRepository;
  final Clock clock;

  static const _reviewOffsets = {
    RevisionPreset.off: <int>[],
    RevisionPreset.light: [1, 3, 7],
    RevisionPreset.standard: [1, 3, 7, 14],
  };

  Future<void> generateRevisionsForTopic(String topicId) async {
    final topic = await topicRepository.getById(topicId);
    if (topic == null) {
      throw const NotFoundException('Topic was not found.');
    }
    if (topic.status != TopicStatus.learned ||
        topic.revisionCycleStartedOn != null) {
      return;
    }

    final settings = await settingsRepository.getSettings();
    final today = clock.today.toString();
    final learnedOn = topic.learnedOn ?? today;
    final offsets = _reviewOffsets[settings.revisionPreset] ?? const <int>[];

    await topicRepository.update(
      topic.copyWith(
        learnedOn: Value(learnedOn),
        revisionCycleStartedOn: Value(today),
      ),
    );

    final base = LocalDate.parse(learnedOn);
    for (var stage = 0; stage < offsets.length; stage++) {
      await taskRepository.insert(
        topicId: topic.id,
        title: 'Revise: ${topic.title}',
        kind: TaskKind.revision,
        priority: 1,
        estimateMinutes: settings.revisionLengthMinutes,
        notBeforeDate: base.addDays(offsets[stage]).toString(),
        revisionStage: stage,
      );
    }
  }
}
