# ClawGate — Design Spec

**Date:** 2026-04-17  
**Status:** Approved, pending implementation  
**Feature:** SSH local port-forward tunnel exposing the OpenClaw web UI in Safari

---

## Problem

OpenClaw runs a web UI on `127.0.0.1:18789` on the VPS. From a desktop you'd run:

```bash
ssh -N -L 18790:127.0.0.1:18789 user@server
```

then open `http://127.0.0.1:18790/#token=...` in a browser. On iPhone there's no terminal to do this, but the app already has an active SSH connection. ClawGate makes this one tap.

---

## Architecture

```
iPhone                                      VPS
┌──────────────────────────────┐           ┌─────────────────────────┐
│  Safari                      │           │  SSH daemon              │
│  http://127.0.0.1:PORT/#tok  │           │        │                 │
│          │ TCP               │           │  direct-tcpip channel   │
│  ServerSocket (dart:io)      │◄─SSH────► │        │                 │
│  ClawGateNotifier            │           │  OpenClaw :18789         │
└──────────────────────────────┘           └─────────────────────────┘
```

**No firewall changes. Token stays in the URL fragment (never sent over the wire).**

---

## User Flow

1. User opens server detail screen for a connected server
2. "Open Clawbot UI" tile is visible (disabled if SSH not connected)
3. User taps tile → spinner: "Starting tunnel…"
4. App runs `openclaw dashboard --no-open` over SSH, parses token from stdout
5. App binds `ServerSocket` on `127.0.0.1:0` (OS assigns free port)
6. Accept loop starts: each incoming connection is piped to `forwardLocal('127.0.0.1', 18789)`
7. `url_launcher` opens Safari to `http://127.0.0.1:PORT/#token=TOKEN`
8. Tile shows green dot + "Tunnel active" + stop button
9. User taps stop (or leaves server detail screen) → `ServerSocket.close()` → tunnel dies cleanly

---

## Files to Create / Modify

### New files
| File | Purpose |
|---|---|
| `lib/features/tunnel/domain/claw_gate_state.dart` | State value type (status enum + port + error) |
| `lib/features/tunnel/presentation/claw_gate_notifier.dart` | Riverpod `StateNotifier` — owns the ServerSocket and accept loop |

### Modified files
| File | Change |
|---|---|
| `lib/features/ssh/domain/ssh_client.dart` | Add `forwardChannel(String host, int port)` abstract method |
| `lib/features/ssh/data/ssh_client_impl.dart` | Implement `forwardChannel` using `_client.forwardLocal()` from dartssh2; return a plain `({Stream<Uint8List> stream, StreamSink<Uint8List> sink})` record so no dartssh2 types leak |
| `lib/features/server_profiles/presentation/server_detail_screen.dart` | Add "Open Clawbot UI" tile; watch `clawGateProvider(serverId)` |
| `pubspec.yaml` | Add `url_launcher: ^6.3.0` |

---

## State Model

```dart
enum ClawGateStatus { idle, fetchingToken, starting, active, error }

class ClawGateState {
  final ClawGateStatus status;
  final int? localPort;       // assigned once ServerSocket binds
  final String? token;        // parsed from openclaw output
  final String? errorMessage;
}
```

---

## ClawGateNotifier Logic

```dart
// Provider — one per server
final clawGateProvider = StateNotifierProvider.family<ClawGateNotifier, ClawGateState, String>(
  (ref, serverId) => ClawGateNotifier(ref, serverId),
);

class ClawGateNotifier extends StateNotifier<ClawGateState> {
  // start():
  //   1. state = fetchingToken
  //   2. client.exec('su - clawd -c '...; openclaw dashboard --no-open'')
  //   3. Parse token: RegExp(r'#token=([^\s&]+)').firstMatch(stdout)
  //   4. If no token → state = error('Could not obtain token')
  //   5. state = starting
  //   6. _server = await ServerSocket.bind('127.0.0.1', 0)
  //   7. state = active(port: _server.port, token: token)
  //   8. url_launcher → launchUrl('http://127.0.0.1:${port}/#token=$token')
  //   9. _acceptLoop(): for each socket → forwardChannel → pipe bytes

  // stop():
  //   1. _server?.close()
  //   2. state = idle
}
```

---

## Token Command

```bash
su - clawd -c 'export PATH="$HOME/.npm-global/bin:$PATH"; openclaw dashboard --no-open'
```

Parse stdout with: `RegExp(r'#token=([^\s&"]+)')`

If exit code is non-zero or no token found → show error with the stderr output so the user knows whether OpenClaw isn't installed or clawd user doesn't exist.

---

## Accept Loop (byte piping)

```dart
_acceptLoop() async {
  await for (final socket in _server!) {
    final channel = await sshClient.forwardChannel('127.0.0.1', 18789);
    socket.listen(channel.sink.add, onDone: channel.sink.close);
    channel.stream.listen(socket.add, onDone: socket.close);
  }
}
```

Each HTTP request from Safari opens a new TCP connection → new SSH channel. Keeps things stateless and simple.

---

## Backgrounding

When iOS suspends the app the `ServerSocket` stops accepting and in-flight connections stall. When the user returns to the app:
- If `_server` is still bound: state remains `active`, user can tap "Open in Browser" again
- If the SSH session died: `sshConnectionProvider` will show disconnected → tile disables + shows "Tunnel stopped — reconnect SSH first"

No silent auto-reconnect. The user must restart explicitly to avoid confusing Safari's open tab.

---

## Error Cases

| Situation | Behaviour |
|---|---|
| SSH not connected | Tile disabled with "Connect first" hint |
| `openclaw` not installed on VPS | Error state: shows stderr, suggests installing OpenClaw |
| Port 18789 not listening on VPS | Safari gets connection refused — tunnel starts but UI fails to load |
| SSH session drops while tunnel active | State stays `active` until user retries; piped connections will error naturally |
| Token not found in output | Error state with raw command output shown |

---

## Dependencies

- `url_launcher: ^6.3.0` — open Safari with the tunnel URL
- `dart:io` `ServerSocket` — already available, no new packages
- `dartssh2` `SSHClient.forwardLocal()` — already in the app, exposed via new `forwardChannel` interface method

---

## Out of Scope (v1)

- In-app WKWebView (Safari is fine for v1)
- Token caching / persistence (tokens are session-scoped)
- Multiple simultaneous tunnels
- Non-OpenClaw ports (easy to generalise later)
