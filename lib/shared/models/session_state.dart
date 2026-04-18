/// Connection state for an SSH session. The UI observes this to show
/// "connecting", "connected", "error" etc.
enum SshConnectionState {
  disconnected,
  connecting,
  connected,
  reconnecting,
  error,
}

class SessionState {
  final String serverId;
  final SshConnectionState connectionState;
  final String? lastError;
  final DateTime? connectedAt;
  final String? hostFingerprint;

  const SessionState({
    required this.serverId,
    this.connectionState = SshConnectionState.disconnected,
    this.lastError,
    this.connectedAt,
    this.hostFingerprint,
  });

  SessionState copyWith({
    SshConnectionState? connectionState,
    String? lastError,
    DateTime? connectedAt,
    String? hostFingerprint,
  }) {
    return SessionState(
      serverId: serverId,
      connectionState: connectionState ?? this.connectionState,
      lastError: lastError,
      connectedAt: connectedAt ?? this.connectedAt,
      hostFingerprint: hostFingerprint ?? this.hostFingerprint,
    );
  }
}
