import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../features/ssh/domain/ssh_client.dart';
import '../../../features/ssh/presentation/ssh_connection_notifier.dart';
import '../../../shared/models/session_state.dart';
import '../domain/claw_gate_state.dart';

// Read gateway.auth.token from ~/.openclaw/openclaw.json if present.
// On 2026.4.5 the installer defaults gateway.auth.mode = "none" with no
// token key — Caddy's basic_auth is the only gate. This python prints
// an empty string (not a KeyError) in that case so the caller treats
// it as "no token, let the WebView handle basic-auth in the browser
// chrome".
const _tokenCommand = r"""su - clawd -c 'export PATH="$HOME/.npm-global/bin:/usr/local/bin:/usr/bin:$PATH"; python3 -c "import json,os; d=json.load(open(os.path.expanduser(\"~/.openclaw/openclaw.json\"))); print((d.get(\"gateway\") or {}).get(\"auth\",{}).get(\"token\") or \"\")" 2>&1'""";

class ClawGateNotifier extends StateNotifier<ClawGateState> {
  final Ref _ref;
  final String _serverId;
  ServerSocket? _server;

  ClawGateNotifier(this._ref, this._serverId)
      : super(const ClawGateState.idle());

  @override
  void dispose() {
    _server?.close();
    super.dispose();
  }

  Future<void> start(TunnelTarget target) async {
    final session = _ref.read(sshConnectionProvider(_serverId));
    if (session.connectionState != SshConnectionState.connected) {
      state = const ClawGateState(
        status: ClawGateStatus.error,
        errorMessage: 'SSH not connected — connect first.',
      );
      return;
    }

    final client = _ref.read(sshClientProvider(_serverId));
    String? token;

    // ── Try to fetch a gateway token ───────────────────────────────────────
    // Both targets (OpenClaw UI and Mission Control) prefer token auth
    // when available — it gives the OpenClaw UI a direct login without
    // a basic-auth prompt. When the token is missing (2026.4.5 default
    // mode "none"), we fall back to basic auth handled by the WebView
    // on the first request. That's not an error; just keep going.
    state = const ClawGateState(status: ClawGateStatus.fetchingToken);
    try {
      final result = await client.exec(_tokenCommand,
          timeout: const Duration(seconds: 8),);
      final fetched = result.stdout.trim();
      token = fetched.isEmpty ? null : fetched;
    } catch (_) {
      // SSH hiccup or exec timeout — not fatal. Proceed tokenless.
      token = null;
    }

    // ── Bind local port ──────────────────────────────────────────────────────
    state = ClawGateState(
        status: ClawGateStatus.starting, activeTarget: target, token: token,);

    try {
      _server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    } catch (e) {
      state = ClawGateState(
        status: ClawGateStatus.error,
        errorMessage: 'Could not bind local port: $e',
      );
      return;
    }

    final port = _server!.port;

    // Start accept loop before surfacing the URL so it's ready when WebView connects.
    _acceptLoop(client, target.remotePort);

    state = ClawGateState(
      status: ClawGateStatus.active,
      activeTarget: target,
      localPort: port,
      token: token,
    );
  }

  Future<void> stop() async {
    await _server?.close();
    _server = null;
    state = const ClawGateState.idle();
  }

  void _acceptLoop(SshClient client, int remotePort) async {
    final server = _server;
    if (server == null) return;
    try {
      await for (final socket in server) {
        _pipe(socket, client, remotePort);
      }
    } catch (_) {
      // Closed by stop() — normal.
    }
  }

  void _pipe(Socket socket, SshClient client, int remotePort) async {
    try {
      final channel = await client.forwardChannel('127.0.0.1', remotePort);

      socket.listen(
        (data) { try { channel.sink.add(data); } catch (_) {} },
        onDone: () { try { channel.sink.close(); } catch (_) {} },
        onError: (_) { try { channel.sink.close(); } catch (_) {} },
        cancelOnError: false,
      );

      channel.stream.listen(
        (data) { try { socket.add(data); } catch (_) {} },
        onDone: () { try { socket.destroy(); } catch (_) {} },
        onError: (_) { try { socket.destroy(); } catch (_) {} },
        cancelOnError: false,
      );
    } catch (_) {
      try { socket.destroy(); } catch (_) {}
    }
  }
}

final clawGateProvider =
    StateNotifierProvider.family<ClawGateNotifier, ClawGateState, String>(
  (ref, serverId) => ClawGateNotifier(ref, serverId),
);
