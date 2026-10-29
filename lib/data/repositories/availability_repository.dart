import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../core/validation.dart';
import '../database/app_database.dart';

class AvailabilityRepository {
  AvailabilityRepository(this._db);

  final AppDatabase _db;

  static const _uuid = Uuid();

  Stream<List<AvailabilityWindow>> watchAll() {
    return (_db.select(_db.availabilityWindows)..orderBy([
          (t) => OrderingTerm.asc(t.weekday),
          (t) => OrderingTerm.asc(t.startMinute),
        ]))
        .watch();
  }

  Future<AvailabilityWindow?> getById(String id) {
    return (_db.select(
      _db.availabilityWindows,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
  }

  Future<AvailabilityWindow> insert({
    required int weekday,
    required int startMinute,
    required int endMinute,
  }) async {
    ValidationRules.validateAvailabilityWindow(
      weekday: weekday,
      startMinute: startMinute,
      endMinute: endMinute,
    );
    await _ensureNoOverlap(
      weekday: weekday,
      startMinute: startMinute,
      endMinute: endMinute,
    );
    final now = DateTime.now().millisecondsSinceEpoch;
    final window = AvailabilityWindow(
      id: _uuid.v4(),
      weekday: weekday,
      startMinute: startMinute,
      endMinute: endMinute,
      createdAt: now,
      updatedAt: now,
    );
    await _db.into(_db.availabilityWindows).insert(window);
    return window;
  }

  Future<void> update(AvailabilityWindow window) async {
    final existing = await getById(window.id);
    if (existing == null) {
      throw NotFoundException(
        'Availability window ${window.id} was not found.',
      );
    }
    ValidationRules.validateAvailabilityWindow(
      weekday: window.weekday,
      startMinute: window.startMinute,
      endMinute: window.endMinute,
    );
    await _ensureNoOverlap(
      weekday: window.weekday,
      startMinute: window.startMinute,
      endMinute: window.endMinute,
      excludeId: window.id,
    );
    final updated = window.copyWith(
      createdAt: existing.createdAt,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );
    await (_db.update(
      _db.availabilityWindows,
    )..where((t) => t.id.equals(window.id))).write(updated.toCompanion(false));
  }

  Future<void> deleteOrArchive(String id) async {
    final window = await getById(id);
    if (window == null) {
      throw NotFoundException('Availability window $id was not found.');
    }
    await (_db.delete(
      _db.availabilityWindows,
    )..where((t) => t.id.equals(id))).go();
  }

  Future<void> _ensureNoOverlap({
    required int weekday,
    required int startMinute,
    required int endMinute,
    String? excludeId,
  }) async {
    final windows = await (_db.select(
      _db.availabilityWindows,
    )..where((t) => t.weekday.equals(weekday))).get();
    for (final other in windows) {
      if (other.id == excludeId) {
        continue;
      }
      if (startMinute < other.endMinute && other.startMinute < endMinute) {
        throw const ConflictException(
          'Availability windows cannot overlap on the same weekday.',
        );
      }
    }
  }
}
