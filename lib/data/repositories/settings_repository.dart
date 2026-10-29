import '../../core/validation.dart';
import '../database/app_database.dart';

class SettingsRepository {
  SettingsRepository(this._db);

  final AppDatabase _db;

  Stream<List<AppSetting>> watchAll() {
    return _db.select(_db.appSettings).watch();
  }

  Future<AppSetting?> getById(int id) {
    return (_db.select(
      _db.appSettings,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
  }

  Future<AppSetting> insert() async {
    final existing = await getById(1);
    if (existing != null) {
      throw const ConflictException('Settings already exist.');
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db
        .into(_db.appSettings)
        .insert(AppSettingsCompanion.insert(createdAt: now, updatedAt: now));
    return (await getById(1))!;
  }

  Future<AppSetting> getSettings() async {
    final settings = await getById(1);
    if (settings != null) {
      return settings;
    }
    return insert();
  }

  Future<void> update(AppSetting settings) async {
    final existing = await getById(settings.id);
    if (existing == null) {
      throw NotFoundException('Settings ${settings.id} were not found.');
    }
    _validate(settings);
    final updated = settings.copyWith(
      createdAt: existing.createdAt,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );
    await (_db.update(_db.appSettings)..where((t) => t.id.equals(settings.id)))
        .write(updated.toCompanion(false));
  }

  Future<void> deleteOrArchive(int id) async {
    final settings = await getById(id);
    if (settings == null) {
      throw NotFoundException('Settings $id were not found.');
    }
    await (_db.delete(_db.appSettings)..where((t) => t.id.equals(id))).go();
  }

  void _validate(AppSetting settings) {
    ValidationRules.validateDailyLimitMinutes(settings.dailyLimitMinutes);
    ValidationRules.validateBlockLengthMinutes(settings.blockLengthMinutes);
    ValidationRules.validateMinSessionMinutes(
      minSessionMinutes: settings.minSessionMinutes,
      blockLengthMinutes: settings.blockLengthMinutes,
    );
    ValidationRules.validateBreakMinutes(settings.breakMinutes);
    ValidationRules.validateHorizonDays(settings.horizonDays);
    ValidationRules.validateRevisionLengthMinutes(
      settings.revisionLengthMinutes,
    );
  }
}
