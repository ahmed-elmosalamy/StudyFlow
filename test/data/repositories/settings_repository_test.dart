import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:studyflow/core/validation.dart';
import 'package:studyflow/data/database/app_database.dart';
import 'package:studyflow/data/database/tables.dart';
import 'package:studyflow/data/repositories/settings_repository.dart';

void main() {
  late AppDatabase db;
  late SettingsRepository settings;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    settings = SettingsRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  test('creates the singleton with defaults when absent', () async {
    expect(await settings.getById(1), isNull);

    final created = await settings.getSettings();
    expect(created.id, 1);
    expect(created.dailyLimitMinutes, 120);
    expect(created.blockLengthMinutes, 50);
    expect(created.minSessionMinutes, 15);
    expect(created.breakMinutes, 10);
    expect(created.horizonDays, 14);
    expect(created.revisionPreset, RevisionPreset.standard);
    expect(created.revisionLengthMinutes, 25);
    expect(created.autoReplan, 1);
    expect(created.themeMode, ThemeModeSetting.system);
    expect(created.dynamicColor, 1);
    expect(created.setupComplete, 0);
    expect(created.planStale, 0);

    final again = await settings.getSettings();
    expect(again.id, created.id);
    expect(await db.select(db.appSettings).get(), hasLength(1));
  });

  test('updates settings and rejects invalid values', () async {
    final current = await settings.getSettings();

    await settings.update(
      current.copyWith(dailyLimitMinutes: 90, autoReplan: 0),
    );
    final updated = (await settings.getById(1))!;
    expect(updated.dailyLimitMinutes, 90);
    expect(updated.autoReplan, 0);

    await expectLater(
      settings.update(updated.copyWith(dailyLimitMinutes: 10)),
      throwsA(isA<ValidationException>()),
    );
    await expectLater(
      settings.update(
        updated.copyWith(minSessionMinutes: 30, blockLengthMinutes: 50),
      ),
      throwsA(isA<ValidationException>()),
    );
  });
}
