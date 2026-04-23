import 'dart:async';
import 'dart:collection';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ssh/presentation/ssh_connection_notifier.dart';
import '../domain/server_health.dart';

/// Public state for the health feature.
class HealthState {
  /// Most recent snapshot. Null until the first poll lands.
  final ServerHealthSnapshot? latest;

  /// Last 30 snapshots (oldest → newest). Used for sparkline history.
  final List<ServerHealthSnapshot> history;

  /// True while a probe is in flight.
  final bool loading;

  /// Last error message, if any. Cleared on next successful poll.
  final String? error;

  /// True when the notifier is actively polling (screen visible + SSH up).
  final bool running;

  const HealthState({
    this.latest,
    this.history = const [],
    this.loading = false,
    this.error,
    this.running = false,
  });

  HealthState copyWith({
    ServerHealthSnapshot? latest,
    List<ServerHealthSnapshot>? history,
    bool? loading,
    String? error,
    bool clearError = false,
    bool? running,
  }) {
    return HealthState(
      latest: latest ?? this.latest,
      history: history ?? this.history,
      loading: loading ?? this.loading,
      error: clearError ? null : (error ?? this.error),
      running: running ?? this.running,
    );
  }
}

const _pollInterval = Duration(seconds: 10);
const _historyCap = 30;

/// Per-server health notifier. Starts/stops polling on demand so screens that
/// aren't visible don't burn SSH round-trips. The SSH connection is re-read
/// on every tick so the first tick after (re)connect picks up automatically.
class ServerHealthNotifier extends StateNotifier<HealthState> {
  final Ref _ref;
  final String _serverId;
  final ServerHealthParser _parser;

  Timer? _timer;
  bool _inFlight = false;

  ServerHealthNotifier(this._ref, this._serverId,
      {ServerHealthParser? parser})
      : _parser = parser ?? const ServerHealthParser(),
        super(const HealthState());

  /// Starts periodic polling. Fires one probe immediately, then every 10s.
  /// Idempotent — calling `start()` twice does not double up timers.
  void start() {
    if (_timer != null && _timer!.isActive) return;
    state = state.copyWith(running: true);
    _timer = Timer.periodic(_pollInterval, (_) => _probe());
    _probe();
  }

  /// Stops polling but keeps the last snapshot in state so the tile can
  /// continue to render while the user navigates away and back.
  void stop() {
    _timer?.cancel();
    _timer = null;
    state = state.copyWith(running: false);
  }

  /// Manual refresh — forces a single probe regardless of polling state.
  Future<void> refresh() async {
    await _probe();
  }

  Future<void> _probe() async {
    if (_inFlight) return;
    _inFlight = true;
    try {
      final client = _ref.read(sshClientProvider(_serverId));
      if (!client.isConnected) {
        // Connection dropped — keep last known but stop showing stale errors.
        state = state.copyWith(loading: false, clearError: true);
        return;
      }
      state = state.copyWith(loading: true);
      final result = await client.exec(
        serverHealthProbeCommand,
        timeout: const Duration(seconds: 8),
      );
      if (result.exitCode != 0 && result.stdout.trim().isEmpty) {
        state = state.copyWith(
          loading: false,
          error: result.stderr.trim().isNotEmpty
              ? result.stderr.trim()
              : 'Probe failed (exit ${result.exitCode})',
        );
        return;
      }
      final snap = _parser.parse(result.stdout);
      final next = List<ServerHealthSnapshot>.from(state.history)..add(snap);
      while (next.length > _historyCap) {
        next.removeAt(0);
      }
      state = state.copyWith(
        latest: snap,
        history: UnmodifiableListView(next).toList(),
        loading: false,
        clearError: true,
      );
    } catch (e) {
      state = state.copyWith(loading: false, error: e.toString());
    } finally {
      _inFlight = false;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

final serverHealthProvider = StateNotifierProvider.family<
    ServerHealthNotifier, HealthState, String>(
  (ref, serverId) => ServerHealthNotifier(ref, serverId),
);
