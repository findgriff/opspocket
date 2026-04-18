import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/database/app_database.dart';
import '../../../shared/providers/db_providers.dart';

/// Simple key/value store for app settings. Values are strings; callers
/// encode/decode. For one-screen MVP we keep this dead simple.
abstract class SettingsRepository {
  Future<String?> get(String key);
  Future<void> set(String key, String value);
  Future<Map<String, String>> all();
  Future<void> remove(String key);
}

class SettingsRepositoryImpl implements SettingsRepository {
  final AppDatabase _db;
  SettingsRepositoryImpl(this._db);

  @override
  Future<String?> get(String key) async {
    final row = await (_db.select(_db.appSettings)..where((t) => t.key.equals(key))).getSingleOrNull();
    return row?.value;
  }

  @override
  Future<void> set(String key, String value) async {
    await _db.into(_db.appSettings).insertOnConflictUpdate(
          AppSettingsCompanion.insert(key: key, value: value),
        );
  }

  @override
  Future<Map<String, String>> all() async {
    final rows = await _db.select(_db.appSettings).get();
    return {for (final r in rows) r.key: r.value};
  }

  @override
  Future<void> remove(String key) async {
    await (_db.delete(_db.appSettings)..where((t) => t.key.equals(key))).go();
  }
}

final settingsRepositoryProvider = Provider<SettingsRepository>((ref) {
  return SettingsRepositoryImpl(ref.watch(appDatabaseProvider));
});

/// Canonical setting keys + typed accessors. Booleans and ints are stored
/// as strings to keep the schema simple.
class SettingKeys {
  SettingKeys._();

  static const biometricLock = 'biometric_lock';
  static const appLockTimeoutSeconds = 'app_lock_timeout_seconds';
  static const defaultLogLines = 'default_log_lines';
  static const terminalFontSize = 'terminal_font_size';
  static const dangerousConfirmation = 'dangerous_confirmation';
  static const sessionTimeoutSeconds = 'session_timeout_seconds';
  static const selectedProviderCredentialId = 'selected_provider_credential_id';
}
