import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/database/app_database.dart';
import '../../../shared/database/mappers.dart';
import '../../../shared/models/server_profile.dart';
import '../../../shared/providers/db_providers.dart';
import '../../../shared/storage/secure_storage.dart';
import '../domain/server_profile_repository.dart';

class ServerProfileRepositoryImpl implements ServerProfileRepository {
  final AppDatabase _db;
  final SecureStorage _secureStorage;

  ServerProfileRepositoryImpl(this._db, this._secureStorage);

  @override
  Stream<List<ServerProfile>> watchAll() {
    final query = _db.select(_db.serverProfiles)
      ..orderBy([
        (t) => OrderingTerm.desc(t.isFavorite),
        (t) => OrderingTerm.asc(t.nickname),
      ]);
    return query.watch().map((rows) => rows.map((r) => r.toModel()).toList());
  }

  @override
  Future<List<ServerProfile>> getAll() async {
    final rows = await _db.select(_db.serverProfiles).get();
    return rows.map((r) => r.toModel()).toList();
  }

  @override
  Future<ServerProfile?> getById(String id) async {
    final row = await (_db.select(_db.serverProfiles)..where((t) => t.id.equals(id))).getSingleOrNull();
    return row?.toModel();
  }

  @override
  Future<void> upsert(ServerProfile profile) async {
    await _db.into(_db.serverProfiles).insertOnConflictUpdate(serverProfileToCompanion(profile));
  }

  @override
  Future<void> delete(String id) async {
    final existing = await getById(id);
    if (existing?.secureStorageKey != null) {
      // Best-effort cleanup of secret bodies. Never block the delete on it.
      try {
        await _secureStorage.delete(key: existing!.secureStorageKey!);
        if (existing.hasPassphrase) {
          await _secureStorage.delete(key: SecretKeys.sshKeyPassphrase(id));
        }
      } catch (_) {}
    }
    await (_db.delete(_db.serverProfiles)..where((t) => t.id.equals(id))).go();
    await (_db.delete(_db.hostFingerprints)..where((t) => t.serverId.equals(id))).go();
  }

  @override
  Future<void> toggleFavorite(String id) async {
    final p = await getById(id);
    if (p == null) return;
    await upsert(p.copyWith(isFavorite: !p.isFavorite, updatedAt: DateTime.now()));
  }

  @override
  Future<void> touchLastConnected(String id, DateTime when) async {
    final p = await getById(id);
    if (p == null) return;
    await upsert(p.copyWith(lastConnectedAt: when, updatedAt: DateTime.now()));
  }
}

final serverProfileRepositoryProvider = Provider<ServerProfileRepository>((ref) {
  return ServerProfileRepositoryImpl(
    ref.watch(appDatabaseProvider),
    ref.watch(secureStorageProvider),
  );
});

final serverProfilesStreamProvider = StreamProvider<List<ServerProfile>>((ref) {
  return ref.watch(serverProfileRepositoryProvider).watchAll();
});

final serverProfileByIdProvider = FutureProvider.family<ServerProfile?, String>((ref, id) {
  return ref.watch(serverProfileRepositoryProvider).getById(id);
});
