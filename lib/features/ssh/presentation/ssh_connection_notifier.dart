import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../app/core/errors/app_error.dart';
import '../../../shared/models/host_fingerprint_record.dart';
import '../../../shared/models/server_profile.dart';
import '../../../shared/models/session_state.dart';
import '../../../shared/storage/secure_storage.dart';
import '../../audit/data/audit_repository_impl.dart';
import '../../server_profiles/data/server_profile_repository_impl.dart';
import '../data/host_fingerprint_repository_impl.dart';
import '../data/ssh_client_impl.dart';
import '../domain/host_fingerprint_repository.dart';
import '../domain/ssh_client.dart';

/// Exposes a single active [SshClient] per server id. Host-key trust is
/// handled here so the raw client stays framework-free.
final sshClientProvider = Provider.family<SshClient, String>((ref, serverId) {
  final client = DartSsh2Client();
  ref.onDispose(() => client.disconnect());
  return client;
});

/// Manages the UI-facing state of an SSH session for a given server.
class SshConnectionNotifier extends StateNotifier<SessionState> {
  final Ref _ref;
  final String _serverId;

  /// Pending host-key decision; exposed so the UI can prompt the user.
  HostKeyChallenge? _pendingChallenge;
  HostKeyChallenge? get pendingChallenge => _pendingChallenge;

  SshConnectionNotifier(this._ref, this._serverId)
      : super(SessionState(serverId: _serverId));

  Future<void> connect() async {
    if (state.connectionState == SshConnectionState.connecting) return;
    state = state.copyWith(
      connectionState: SshConnectionState.connecting,
      lastError: null,
    );

    try {
      final profile = await _ref.read(serverProfileRepositoryProvider).getById(_serverId);
      if (profile == null) {
        throw const ValidationError('Server profile not found');
      }
      if (profile.authMethod == SshAuthMethod.privateKey && profile.secureStorageKey == null) {
        throw const ValidationError('No private key stored for this server');
      }

      final storage = _ref.read(secureStorageProvider);
      String? pem;
      String? passphrase;
      String? password;
      if (profile.authMethod == SshAuthMethod.privateKey) {
        pem = await storage.read(key: profile.secureStorageKey!);
        if (pem == null) {
          throw const ValidationError('Private key missing from secure storage');
        }
        if (profile.hasPassphrase) {
          passphrase = await storage.read(key: SecretKeys.sshKeyPassphrase(profile.id));
        }
      } else {
        password = await storage.read(key: SecretKeys.sshPassword(profile.id));
        if (password == null) {
          throw const ValidationError('No password stored for this server');
        }
      }

      final client = _ref.read(sshClientProvider(_serverId));
      final fpRepo = _ref.read(hostFingerprintRepositoryProvider);

      await client.connect(
        profile: profile,
        creds: SshCredentials(
          privateKeyPem: pem,
          passphrase: passphrase,
          password: password,
        ),
        onHostKey: (challenge) async {
          final stored = await fpRepo.getForServer(profile.id);
          final reconciled = HostKeyChallenge(
            presentedFingerprint: challenge.presentedFingerprint,
            storedFingerprint: stored?.fingerprint,
          );
          return await _resolveHostKey(reconciled, profile, fpRepo);
        },
      );

      await _ref.read(serverProfileRepositoryProvider).touchLastConnected(
            profile.id,
            DateTime.now(),
          );

      await _ref.read(auditRepositoryProvider).log(
            serverId: profile.id,
            serverNickname: profile.nickname,
            actionType: 'sshConnect',
            transport: 'ssh',
            success: true,
            rawCommand: null,
            commandTemplateName: null,
            shortOutputSummary: 'Fingerprint: ${client.currentFingerprint}',
            errorSummary: null,
          );

      state = state.copyWith(
        connectionState: SshConnectionState.connected,
        connectedAt: DateTime.now(),
        hostFingerprint: client.currentFingerprint,
        lastError: null,
      );
    } on AppError catch (e) {
      await _logFailure(e.message);
      state = state.copyWith(
        connectionState: SshConnectionState.error,
        lastError: e.message,
      );
    } catch (e, st) {
      if (kDebugMode) debugPrint('SSH connect error: $e\n$st');
      await _logFailure(e.toString());
      state = state.copyWith(
        connectionState: SshConnectionState.error,
        lastError: 'Connection failed',
      );
    }
  }

  Future<bool> _resolveHostKey(
    HostKeyChallenge challenge,
    ServerProfile profile,
    HostFingerprintRepository repo,
  ) async {
    if (challenge.isFirstContact) {
      // Trust-on-first-use. The UI surfaces the fingerprint in the
      // connection banner; we record it so mismatches block on later connects.
      await repo.upsert(HostFingerprintRecord(
        id: const Uuid().v4(),
        serverId: profile.id,
        hostnameOrIp: profile.hostnameOrIp,
        port: profile.port,
        fingerprint: challenge.presentedFingerprint,
        acceptedAt: DateTime.now(),
        lastSeenAt: DateTime.now(),
      ),);
      return true;
    }
    if (challenge.isMismatch) {
      _pendingChallenge = challenge;
      // Hard-fail; UI will surface an explicit warning and allow clearing.
      throw HostFingerprintMismatchError(
        expected: challenge.storedFingerprint!,
        actual: challenge.presentedFingerprint,
      );
    }
    // Match — just bump lastSeenAt.
    final existing = await repo.getForServer(profile.id);
    if (existing != null) {
      await repo.upsert(HostFingerprintRecord(
        id: existing.id,
        serverId: existing.serverId,
        hostnameOrIp: existing.hostnameOrIp,
        port: existing.port,
        fingerprint: existing.fingerprint,
        acceptedAt: existing.acceptedAt,
        lastSeenAt: DateTime.now(),
      ),);
    }
    return true;
  }

  Future<void> disconnect() async {
    try {
      await _ref.read(sshClientProvider(_serverId)).disconnect();
    } catch (_) {}
    state = state.copyWith(
      connectionState: SshConnectionState.disconnected,
      lastError: null,
    );
  }

  Future<void> _logFailure(String msg) async {
    try {
      final profile = await _ref.read(serverProfileRepositoryProvider).getById(_serverId);
      await _ref.read(auditRepositoryProvider).log(
            serverId: _serverId,
            serverNickname: profile?.nickname,
            actionType: 'sshConnect',
            transport: 'ssh',
            success: false,
            rawCommand: null,
            commandTemplateName: null,
            shortOutputSummary: null,
            errorSummary: msg,
          );
    } catch (_) {}
  }

  /// User accepted a mismatched host key by clearing the stored fingerprint.
  Future<void> trustNewFingerprint() async {
    final challenge = _pendingChallenge;
    if (challenge == null) return;
    await _ref.read(hostFingerprintRepositoryProvider).deleteForServer(_serverId);
    _pendingChallenge = null;
    await connect();
  }
}

final sshConnectionProvider = StateNotifierProvider.family<SshConnectionNotifier, SessionState, String>(
  (ref, serverId) => SshConnectionNotifier(ref, serverId),
);
