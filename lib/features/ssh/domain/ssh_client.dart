import '../../../shared/models/command_execution_result.dart';
import '../../../shared/models/server_profile.dart';
import 'ssh_forward_channel.dart';

/// Callback invoked on first connect (no prior fingerprint) or when the
/// presented fingerprint doesn't match the stored one. The host-fingerprint
/// resolution strategy lives outside the SSH client so we can keep its
/// implementation pure.
typedef HostKeyCallback = Future<bool> Function(
  HostKeyChallenge challenge,
);

class HostKeyChallenge {
  /// sha256 fingerprint in `SHA256:base64...` form.
  final String presentedFingerprint;

  /// Existing stored fingerprint, if any. If null, this is first contact.
  final String? storedFingerprint;

  const HostKeyChallenge({
    required this.presentedFingerprint,
    this.storedFingerprint,
  });

  bool get isFirstContact => storedFingerprint == null;
  bool get isMismatch => storedFingerprint != null && storedFingerprint != presentedFingerprint;
}

/// Minimal secrets passed to an SSH connection. Kept as a plain value type so
/// the raw key body never ends up in a persistent object.
class SshCredentials {
  final String? privateKeyPem;
  final String? passphrase;
  final String? password;

  const SshCredentials({this.privateKeyPem, this.passphrase, this.password});
}

/// Abstraction over an SSH connection. Implementations may use dartssh2 today
/// and a native bridge tomorrow; the rest of the app is unaffected.
abstract class SshClient {
  bool get isConnected;

  /// Current host fingerprint, populated after a successful connect.
  String? get currentFingerprint;

  /// Connect to the remote host. Throws AppError subtypes on failure.
  Future<void> connect({
    required ServerProfile profile,
    required SshCredentials creds,
    required HostKeyCallback onHostKey,
    Duration? connectTimeout,
  });

  /// Execute a single shell command (exec mode, not PTY). Safer for mobile
  /// networks and matches the recovery use case. stdout/stderr are captured
  /// to the returned [CommandExecutionResult].
  Future<CommandExecutionResult> exec(
    String command, {
    Duration? timeout,
  });

  Future<void> disconnect();

  /// Opens a direct-tcpip channel forwarding to [remoteHost]:[remotePort] on
  /// the server. Equivalent to one connection in `ssh -L local:remote`.
  /// The returned [SshForwardChannel] is ready to pipe bytes immediately.
  Future<SshForwardChannel> forwardChannel(String remoteHost, int remotePort);
}
