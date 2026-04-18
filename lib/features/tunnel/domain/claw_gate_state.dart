enum ClawGateStatus { idle, fetchingToken, starting, active, error }

enum TunnelTarget { clawbot, missionControl }

extension TunnelTargetX on TunnelTarget {
  String get label => switch (this) {
        TunnelTarget.clawbot => 'OpenClaw UI',
        TunnelTarget.missionControl => 'Mission Control',
      };

  /// Remote port on the VPS to forward to.
  int get remotePort => switch (this) {
        TunnelTarget.clawbot => 18789,
        TunnelTarget.missionControl => 80, // Nginx serves /mission-control
      };
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
    return switch (activeTarget) {
      TunnelTarget.clawbot when token != null =>
        'http://127.0.0.1:$localPort/#token=$token',
      TunnelTarget.missionControl =>
        'http://127.0.0.1:$localPort/mission-control',
      _ => null,
    };
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
