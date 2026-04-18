import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../app/core/errors/app_error.dart';

/// Thin wrapper around flutter_secure_storage so the rest of the app never
/// imports the plugin directly. Swap the backing store in tests by overriding
/// [secureStorageProvider].
abstract class SecureStorage {
  Future<void> write({required String key, required String value});
  Future<String?> read({required String key});
  Future<void> delete({required String key});
  Future<bool> containsKey(String key);
  Future<void> deleteAll();
}

class SecureStorageImpl implements SecureStorage {
  final FlutterSecureStorage _storage;

  SecureStorageImpl([FlutterSecureStorage? storage])
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(
                encryptedSharedPreferences: true,
              ),
              iOptions: IOSOptions(
                accessibility: KeychainAccessibility.first_unlock_this_device,
              ),
            );

  @override
  Future<void> write({required String key, required String value}) async {
    try {
      await _storage.write(key: key, value: value);
    } catch (e) {
      throw SecureStorageError('Failed to write secret', cause: e);
    }
  }

  @override
  Future<String?> read({required String key}) async {
    try {
      return await _storage.read(key: key);
    } catch (e) {
      throw SecureStorageError('Failed to read secret', cause: e);
    }
  }

  @override
  Future<void> delete({required String key}) async {
    try {
      await _storage.delete(key: key);
    } catch (e) {
      throw SecureStorageError('Failed to delete secret', cause: e);
    }
  }

  @override
  Future<bool> containsKey(String key) async {
    try {
      return await _storage.containsKey(key: key);
    } catch (e) {
      throw SecureStorageError('Failed to check secret', cause: e);
    }
  }

  @override
  Future<void> deleteAll() async {
    try {
      await _storage.deleteAll();
    } catch (e) {
      throw SecureStorageError('Failed to clear storage', cause: e);
    }
  }
}

final secureStorageProvider = Provider<SecureStorage>((ref) {
  return SecureStorageImpl();
});

/// Secret keys used by the app. Centralized so we never typo.
class SecretKeys {
  SecretKeys._();

  static String sshPrivateKey(String id) => 'ssh.key.$id';
  static String sshKeyPassphrase(String id) => 'ssh.pass.$id';
  static String sshPassword(String id) => 'ssh.pwd.$id';
  static String providerToken(String id) => 'provider.token.$id';
}
