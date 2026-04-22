// Tests for mcBridgeUrlProvider + mcBridgeClientProvider — specifically
// the host-override + password wiring added for Mission Control on
// 2026-04-22.
//
// We don't spin a real HTTP server — the providers just produce a URL and
// a configured client. We inject a fake SecureStorage and a fake server
// profile stream to drive the logic.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:opspocket/features/mission_control/data/mc_bridge_client.dart';
import 'package:opspocket/features/server_profiles/data/server_profile_repository_impl.dart';
import 'package:opspocket/shared/models/server_profile.dart';
import 'package:opspocket/shared/storage/secure_storage.dart';

class _InMemorySecureStorage implements SecureStorage {
  final Map<String, String> _m = {};
  @override
  Future<void> write({required String key, required String value}) async {
    _m[key] = value;
  }

  @override
  Future<String?> read({required String key}) async => _m[key];
  @override
  Future<void> delete({required String key}) async {
    _m.remove(key);
  }

  @override
  Future<bool> containsKey(String key) async => _m.containsKey(key);
  @override
  Future<void> deleteAll() async => _m.clear();
}

ServerProfile _profile(String id, String host) => ServerProfile(
      id: id,
      nickname: 'test',
      hostnameOrIp: host,
      port: 22,
      username: 'root',
      authMethod: SshAuthMethod.privateKey,
      privateKeyLabel: null,
      secureStorageKey: null,
      hasPassphrase: false,
      tags: const [],
      notes: null,
      providerType: ProviderType.none,
      providerResourceId: null,
      isFavorite: false,
      lastConnectedAt: null,
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
    );

ProviderContainer _container(
  _InMemorySecureStorage storage,
  ServerProfile profile,
) {
  return ProviderContainer(
    overrides: [
      secureStorageProvider.overrideWithValue(storage),
      serverProfileByIdProvider(profile.id)
          .overrideWith((ref) async => profile),
    ],
  );
}

void main() {
  group('mcBridgeUrlProvider', () {
    test('uses SSH host when no override set', () async {
      final storage = _InMemorySecureStorage();
      final p = _profile('srv1', 'example.com');
      final c = _container(storage, p);
      addTearDown(c.dispose);

      final uri = await c.read(mcBridgeUrlProvider('srv1').future);
      expect(uri, isNotNull);
      expect(uri.toString(), 'https://example.com/mcp');
    });

    test('uses Keychain override when set', () async {
      final storage = _InMemorySecureStorage();
      await storage.write(
        key: SecretKeys.clawmineHost('srv1'),
        value: 'claw.other.example.com',
      );
      // SSH host is a raw IP (no TLS cert) — typical real-world split.
      final p = _profile('srv1', '178.104.242.211');
      final c = _container(storage, p);
      addTearDown(c.dispose);

      final uri = await c.read(mcBridgeUrlProvider('srv1').future);
      expect(uri.toString(), 'https://claw.other.example.com/mcp');
    });

    test('accepts a full URL override and appends /mcp once', () async {
      final storage = _InMemorySecureStorage();
      await storage.write(
        key: SecretKeys.clawmineHost('srv1'),
        value: 'https://claw.example.com/base',
      );
      final p = _profile('srv1', 'wont.be.used');
      final c = _container(storage, p);
      addTearDown(c.dispose);

      final uri = await c.read(mcBridgeUrlProvider('srv1').future);
      expect(uri.toString(), 'https://claw.example.com/base/mcp');
    });

    test('does not double-append /mcp when override already has it',
        () async {
      final storage = _InMemorySecureStorage();
      await storage.write(
        key: SecretKeys.clawmineHost('srv1'),
        value: 'https://claw.example.com/mcp',
      );
      final p = _profile('srv1', 'wont.be.used');
      final c = _container(storage, p);
      addTearDown(c.dispose);

      final uri = await c.read(mcBridgeUrlProvider('srv1').future);
      expect(uri.toString(), 'https://claw.example.com/mcp');
    });

    test('empty override string falls through to SSH host', () async {
      final storage = _InMemorySecureStorage();
      await storage.write(
        key: SecretKeys.clawmineHost('srv1'),
        value: '   ',
      );
      final p = _profile('srv1', 'fallback.example.com');
      final c = _container(storage, p);
      addTearDown(c.dispose);

      final uri = await c.read(mcBridgeUrlProvider('srv1').future);
      expect(uri.toString(), 'https://fallback.example.com/mcp');
    });

    test('returns null when neither SSH host nor override are set', () async {
      final storage = _InMemorySecureStorage();
      final p = _profile('srv1', '');
      final c = _container(storage, p);
      addTearDown(c.dispose);

      final uri = await c.read(mcBridgeUrlProvider('srv1').future);
      expect(uri, isNull);
    });
  });

  group('mcBridgeClientProvider', () {
    test('produces a client with basic-auth when password is stored',
        () async {
      final storage = _InMemorySecureStorage();
      await storage.write(
        key: SecretKeys.clawminePassword('srv1'),
        value: 'secret',
      );
      final p = _profile('srv1', 'example.com');
      final c = _container(storage, p);
      addTearDown(c.dispose);

      final client = await c.read(mcBridgeClientProvider('srv1').future);
      expect(client, isNotNull);
      expect(client!.basicAuthHeader, isNotNull);
      expect(
        client.basicAuthHeader,
        McBridgeClient.basicAuth('clawmine', 'secret'),
      );
    });

    test('produces a client with null auth when password is missing',
        () async {
      final storage = _InMemorySecureStorage();
      final p = _profile('srv1', 'example.com');
      final c = _container(storage, p);
      addTearDown(c.dispose);

      final client = await c.read(mcBridgeClientProvider('srv1').future);
      expect(client, isNotNull);
      expect(client!.basicAuthHeader, isNull);
    });
  });

  group('SecretKeys (Mission Control)', () {
    test('host key format is stable', () {
      expect(SecretKeys.clawmineHost('abc'), 'clawmine.host.abc');
    });
    test('password key format matches legacy clawmineSecretKey', () {
      expect(SecretKeys.clawminePassword('abc'), 'clawmine.pwd.abc');
      // Backwards-compat alias defined in mc_bridge_client.dart.
      expect(clawmineSecretKey('abc'), SecretKeys.clawminePassword('abc'));
    });
  });
}
