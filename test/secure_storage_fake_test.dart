import 'package:flutter_test/flutter_test.dart';
import 'package:opspocket/shared/storage/secure_storage.dart';

/// An in-memory SecureStorage we can use from any test without touching the
/// platform channel.
class InMemorySecureStorage implements SecureStorage {
  final Map<String, String> _m = {};

  @override
  Future<void> write({required String key, required String value}) async => _m[key] = value;

  @override
  Future<String?> read({required String key}) async => _m[key];

  @override
  Future<void> delete({required String key}) async => _m.remove(key);

  @override
  Future<bool> containsKey(String key) async => _m.containsKey(key);

  @override
  Future<void> deleteAll() async => _m.clear();
}

void main() {
  group('SecureStorage contract (in-memory fake)', () {
    late InMemorySecureStorage s;
    setUp(() => s = InMemorySecureStorage());

    test('write/read round-trips', () async {
      await s.write(key: 'k', value: 'v');
      expect(await s.read(key: 'k'), 'v');
    });

    test('returns null for missing keys', () async {
      expect(await s.read(key: 'missing'), isNull);
    });

    test('delete removes a key', () async {
      await s.write(key: 'a', value: '1');
      await s.delete(key: 'a');
      expect(await s.containsKey('a'), isFalse);
    });

    test('deleteAll clears everything', () async {
      await s.write(key: 'a', value: '1');
      await s.write(key: 'b', value: '2');
      await s.deleteAll();
      expect(await s.read(key: 'a'), isNull);
      expect(await s.read(key: 'b'), isNull);
    });

    test('SecretKeys helpers compose stable keys', () {
      expect(SecretKeys.sshPrivateKey('abc'), 'ssh.key.abc');
      expect(SecretKeys.sshKeyPassphrase('abc'), 'ssh.pass.abc');
      expect(SecretKeys.providerToken('xyz'), 'provider.token.xyz');
    });
  });
}
