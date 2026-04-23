enum ClawGateStatus { idle, fetchingToken, starting, active, error }

/// Two tunnel destinations — both are server-side OpenClaw pages. On
/// OpenClaw 2026.4.5 they point at the same daemon (`127.0.0.1:18789`);
/// the only difference is which view the WebView lands on. On legacy
/// boxes (< 2026), `missionControl` mapped to nginx-served
/// `http://<host>:80/mission-control`. New boxes collapse both to the
/// same backend.
enum TunnelTarget { clawbot, missionControl }

extension TunnelTargetX on TunnelTarget {
  String get label => switch (this) {
        TunnelTarget.clawbot => 'OpenClaw UI',
        TunnelTarget.missionControl => 'Mission Control',
      };

  /// Remote port on the VPS to forward to. Both targets talk to the
  /// OpenClaw daemon on 18789 — auth is handled by the WebView
  /// (Caddy-fronted boxes prompt for basic-auth; token-auth boxes
  /// embed the token in the URL via [ClawGateState.tunnelUrl]).
  int get remotePort => 18789;
}

class ClawGateState {
  final ClawGateStatus status;
  final TunnelTarget? activeTarget;
  final int? localPort;
  final String? token;
  final String? errorMessage;

  const ClawGateState({
    required this.status,
    this.activeTarget,
    this.localPort,
    this.token,
    this.errorMessage,
  });

  const ClawGateState.idle() : this(status: ClawGateStatus.idle);

  bool get isActive => status == ClawGateStatus.active;

  bool get isBusy =>
      status == ClawGateStatus.fetchingToken ||
      status == ClawGateStatus.starting;

  String? get tunnelUrl {
    if (!isActive || localPort == null) return null;
    // Token-auth boxes embed the token in the URL fragment so the
    // OpenClaw UI can pick it up client-side. On basic-auth boxes
    // (2026.4.5 Caddy default — gateway.auth.mode == "none"), the
    // WebView will surface the 401 auth dialog and the user types
    // their clawmine password. Either way, same base URL.
    final base = 'http://127.0.0.1:$localPort/';
    return token != null ? '$base#token=$token' : base;
  }

  ClawGateState copyWith({
    ClawGateStatus? status,
    TunnelTarget? activeTarget,
    int? localPort,
    String? token,
    String? errorMessage,
  }) {
    return ClawGateState(
      status: status ?? this.status,
      activeTarget: activeTarget ?? this.activeTarget,
      localPort: localPort ?? this.localPort,
      token: token ?? this.token,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}
