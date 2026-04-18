import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../shared/database/app_database.dart';
import '../../../shared/database/mappers.dart';
import '../../../shared/models/provider_credential.dart';
import '../../../shared/models/server_profile.dart';
import '../../../shared/providers/db_providers.dart';
import '../../../shared/storage/secure_storage.dart';

abstract class ProviderCredentialRepository {
  Stream<List<ProviderCredential>> watchAll({ProviderType? type});
  Future<List<ProviderCredential>> getAll({ProviderType? type});
  Future<ProviderCredential?> getById(String id);
  Future<ProviderCredential> create({
    required ProviderType type,
    required String label,
    required String token,
  });
  Future<void> delete(String id);
  Future<String?> readToken(String id);
}

class ProviderCredentialRepositoryImpl implements ProviderCredentialRepository {
  final AppDatabase _db;
  final SecureStorage _storage;
  ProviderCredentialRepositoryImpl(this._db, this._storage);

  @override
  Stream<List<ProviderCredential>> watchAll({ProviderType? type}) {
    final q = _db.select(_db.providerCredentials)
      ..orderBy([(t) => OrderingTerm.asc(t.label)]);
    if (type != null) q.where((t) => t.providerType.equals(type.name));
    return q.watch().map((rows) => rows.map((r) => r.toModel()).toList());
  }

  @override
  Future<List<ProviderCredential>> getAll({ProviderType? type}) async {
    final q = _db.select(_db.providerCredentials);
    if (type != null) q.where((t) => t.providerType.equals(type.name));
    final rows = await q.get();
    return rows.map((r) => r.toModel()).toList();
  }

  @override
  Future<ProviderCredential?> getById(String id) async {
    final row = await (_db.select(_db.providerCredentials)..where((t) => t.id.equals(id))).getSingleOrNull();
    return row?.toModel();
  }

  @override
  Future<ProviderCredential> create({
    required ProviderType type,
    required String label,
    required String token,
  }) async {
    final id = const Uuid().v4();
    final key = SecretKeys.providerToken(id);
    await _storage.write(key: key, value: token);
    final cred = ProviderCredential(
      id: id,
      providerType: type,
      label: label,
      secureStorageKey: key,
      createdAt: DateTime.now(),
    );
    await _db.into(_db.providerCredentials).insertOnConflictUpdate(providerCredentialToCompanion(cred));
    return cred;
  }

  @override
  Future<void> delete(String id) async {
    final c = await getById(id);
    if (c != null) {
      try {
        await _storage.delete(key: c.secureStorageKey);
      } catch (_) {}
    }
    await (_db.delete(_db.providerCredentials)..where((t) => t.id.equals(id))).go();
  }

  @override
  Future<String?> readToken(String id) async {
    final c = await getById(id);
    if (c == null) return null;
    return _storage.read(key: c.secureStorageKey);
  }
}

final providerCredentialRepositoryProvider = Provider<ProviderCredentialRepository>((ref) {
  return ProviderCredentialRepositoryImpl(
    ref.watch(appDatabaseProvider),
    ref.watch(secureStorageProvider),
  );
});

final providerCredentialsStreamProvider =
    StreamProvider.family<List<ProviderCredential>, ProviderType?>((ref, type) {
  return ref.watch(providerCredentialRepositoryProvider).watchAll(type: type);
});
