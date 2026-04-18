import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/database/app_database.dart';
import '../../../shared/database/mappers.dart';
import '../../../shared/models/host_fingerprint_record.dart';
import '../../../shared/providers/db_providers.dart';
import '../domain/host_fingerprint_repository.dart';

class HostFingerprintRepositoryImpl implements HostFingerprintRepository {
  final AppDatabase _db;
  HostFingerprintRepositoryImpl(this._db);

  @override
  Future<HostFingerprintRecord?> getForServer(String serverId) async {
    final row = await (_db.select(_db.hostFingerprints)
          ..where((t) => t.serverId.equals(serverId)))
        .getSingleOrNull();
    return row?.toModel();
  }

  @override
  Future<void> upsert(HostFingerprintRecord record) async {
    await _db.into(_db.hostFingerprints).insertOnConflictUpdate(hostFingerprintToCompanion(record));
  }

  @override
  Future<void> deleteForServer(String serverId) async {
    await (_db.delete(_db.hostFingerprints)..where((t) => t.serverId.equals(serverId))).go();
  }
}

final hostFingerprintRepositoryProvider = Provider<HostFingerprintRepository>((ref) {
  return HostFingerprintRepositoryImpl(ref.watch(appDatabaseProvider));
});
