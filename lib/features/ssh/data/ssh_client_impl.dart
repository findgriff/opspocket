import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';

import '../../../app/core/constants/app_constants.dart';
import '../../../app/core/errors/app_error.dart';
import '../../../shared/models/command_execution_result.dart';
import '../../../shared/models/server_profile.dart';
import '../domain/ssh_client.dart';
import '../domain/ssh_forward_channel.dart';

/// dartssh2-backed implementation. Lives entirely behind [SshClient] so we
/// can swap it for a native bridge without touching presentation code.
class DartSsh2Client implements SshClient {
  SSHClient? _client;
  String? _fingerprint;

  @override
  bool get isConnected => _client != null;

  @override
  String? get currentFingerprint => _fingerprint;

  @override
  Future<void> connect({
    required ServerProfile profile,
    required SshCredentials creds,
    required HostKeyCallback onHostKey,
    Duration? connectTimeout,
  }) async {
    await disconnect();

    SSHSocket socket;
    try {
      socket = await SSHSocket.connect(
        profile.hostnameOrIp,
        profile.port,
        timeout: connectTimeout ?? AppConstants.sshConnectTimeout,
      );
    } on SocketException catch (e) {
      throw SshUnreachableError('Host unreachable: ${e.osError?.message ?? e.message}', cause: e);
    } on TimeoutException catch (e) {
      throw SshTimeoutError('Connection timed out', cause: e);
    }

    final fingerprintCompleter = Completer<bool>();

    SSHClient? client;
    try {
      client = SSHClient(
        socket,
        username: profile.username,
        identities: _buildIdentities(creds),
        onPasswordRequest: () => creds.password ?? '',
        onVerifyHostKey: (type, fingerprint) {
          _fingerprint = _formatFingerprint(type, fingerprint);
          // Callback fires during the transport handshake; we capture the
          // fingerprint now and validate user trust after auth completes.
          if (!fingerprintCompleter.isCompleted) {
            fingerprintCompleter.complete(true);
          }
          return true;
        },
      );

      await client.authenticated.timeout(connectTimeout ?? AppConstants.sshConnectTimeout);
    } on SSHAuthFailError catch (e) {
      client?.close();
      throw SshAuthError('Authentication failed', cause: e);
    } on TimeoutException catch (e) {
      client?.close();
      throw SshTimeoutError('Auth timed out', cause: e);
    } on SSHError catch (e) {
      client?.close();
      throw SshAuthError('SSH error: $e', cause: e);
    } catch (e) {
      client?.close();
      throw SshAuthError('SSH connection failed', cause: e);
    }

    // Ensure the host-key callback actually fired.
    try {
      await fingerprintCompleter.future.timeout(const Duration(seconds: 5));
    } on TimeoutException {
      client.close();
      throw const SshTimeoutError('Host key verification timed out');
    }

    // After auth, ask the caller whether this fingerprint is trusted.
    final fp = _fingerprint;
    if (fp == null) {
      client.close();
      throw const SshAuthError('Host key unavailable');
    }

    final accepted = await onHostKey(
      HostKeyChallenge(presentedFingerprint: fp),
    );
    if (!accepted) {
      client.close();
      throw const SshAuthError('Host key rejected');
    }

    _client = client;
  }

  List<SSHKeyPair> _buildIdentities(SshCredentials creds) {
    if (creds.privateKeyPem == null || creds.privateKeyPem!.trim().isEmpty) {
      return const [];
    }
    try {
      return SSHKeyPair.fromPem(creds.privateKeyPem!, creds.passphrase);
    } catch (e) {
      throw SshAuthError('Private key could not be parsed (wrong passphrase?)', cause: e);
    }
  }

  /// Formats the MD5 fingerprint dartssh2 hands us into OpenSSH-style hex.
  /// Not cryptographically strong — used only as a stable identifier so we
  /// can detect host-key changes between connects.
  String _formatFingerprint(String type, Uint8List md5Fingerprint) {
    final hex = md5Fingerprint
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join(':');
    return 'MD5:$hex ($type)';
  }

  @override
  Future<CommandExecutionResult> exec(String command, {Duration? timeout}) async {
    final client = _client;
    if (client == null) {
      throw const SshAuthError('Not connected');
    }
    final started = DateTime.now();
    final effectiveTimeout = timeout ?? AppConstants.sshCommandTimeout;

    try {
      final session = await client.execute(command);
      final stdoutBuf = StringBuffer();
      final stderrBuf = StringBuffer();

      final stdoutFuture = session.stdout.map(utf8.decode).forEach(stdoutBuf.write);
      final stderrFuture = session.stderr.map(utf8.decode).forEach(stderrBuf.write);

      final done = Future.wait([stdoutFuture, stderrFuture, session.done]);
      var timedOut = false;
      try {
        await done.timeout(effectiveTimeout);
      } on TimeoutException {
        timedOut = true;
        try {
          session.kill(SSHSignal.KILL);
        } catch (_) {}
      }

      final finished = DateTime.now();
      return CommandExecutionResult(
        command: command,
        stdout: stdoutBuf.toString(),
        stderr: stderrBuf.toString(),
        exitCode: timedOut ? null : session.exitCode,
        duration: finished.difference(started),
        startedAt: started,
        finishedAt: finished,
        timedOut: timedOut,
      );
    } on SSHError catch (e) {
      final finished = DateTime.now();
      return CommandExecutionResult(
        command: command,
        stdout: '',
        stderr: 'SSH error: $e',
        exitCode: -1,
        duration: finished.difference(started),
        startedAt: started,
        finishedAt: finished,
      );
    }
  }

  @override
  Future<SshForwardChannel> forwardChannel(
      String remoteHost, int remotePort,) async {
    final client = _client;
    if (client == null) throw const SshAuthError('Not connected');
    final ch = await client.forwardLocal(remoteHost, remotePort);
    return SshForwardChannel(stream: ch.stream, sink: ch.sink);
  }

  @override
  Future<void> disconnect() async {
    try {
      _client?.close();
    } catch (_) {}
    _client = null;
    _fingerprint = null;
  }
}

