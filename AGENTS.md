# AGENTS.md — OpsPocket Agent Guide

**Purpose:** Quick-orient an AI coding agent (Claude, GPT, etc.) working on this repo. For the full authoritative state, always read `HANDOVER.md` first.

---

## What this project is

OpsPocket — a Flutter/iOS mobile app for SSH / OpenClaw VPS management. iPhone-first, security-conscious, dark red/black/cyan theme. The app pairs general VPS ops with first-class AI-native features (OpenClaw agents, Mission Control, The Bridge MCP socket).

**Bundle ID:** `co.opspocket.opspocket`
**Flutter:** 3.41.7 / Dart 3.11.5
**State:** Riverpod (`StateNotifierProvider.family` for per-server features)

---

## Architecture you must follow

```
lib/
  app/              router, theme, core utilities
  features/
    ssh/            — SSH + SFTP, dartssh2 hidden behind SshClient / SftpSession
    terminal/       — interactive terminal screen
    files/          — SFTP file browser (new)
    server_health/  — live resource tiles (new)
    server_profiles/ — server CRUD + detail screen
    command_templates/ — slash palette + builtins
    quick_actions/  — tile-based one-tap commands
    tunnel/         — ClawGate: SSH tunnel → WebView (OpenClaw UI, Mission Control)
    mission_control/ — one-tap deploy script
    audit/          — audit log
    settings/
    splash/         — logo splash
    auth_security/  — biometric unlock
  shared/
    database/   — Drift (SQLite)
    models/     — plain value types (server_profile, quick_action, etc.)
    providers/  — cross-feature Riverpod
    storage/    — flutter_secure_storage wrapper
```

Each feature directory contains `domain/` (pure types), `data/` (repositories), and `presentation/` (Flutter widgets + notifiers). Stay inside this pattern — do not put widgets in `domain/` or SSH wire calls in `presentation/`.

---

## Rules that will save you time

1. **Never import `dartssh2` from feature code.** All SSH access goes through `SshClient` (in `features/ssh/domain/ssh_client.dart`). All SFTP goes through `SftpSession` (same dir). If a capability is missing, extend the interface first, implement in `features/ssh/data/`, then use it.

2. **Theme lives in `AppTheme`.** Never hardcode colours. Use `AppTheme.accent` (red), `AppTheme.cyan`, `AppTheme.muted`, `AppTheme.danger`, `AppTheme.warning`. For monospace text: `AppTheme.mono(size: N, color: ...)`.

3. **Per-server state is `StateNotifierProvider.family<Notifier, State, String>`.** The `String` is always the server id. Follow the pattern used in `sshConnectionProvider`, `deployProvider`, `serverHealthProvider`, `sftpBrowserProvider`.

4. **Routes live in `lib/app/router/app_router.dart`.** New screens under `/servers/:id/*` become a `GoRoute` inside the existing `':id'` subroute block.

5. **Secrets go through `SecretKeys` in `lib/shared/storage/secure_storage.dart`.** Never invent key names inline.

6. **After any model or Drift schema change:** `dart run build_runner build --delete-conflicting-outputs`. The CI / tests will fail otherwise.

7. **Stable IDs for builtins.** `builtin.<category>.<slug>` — changing an existing one creates duplicates on user devices because they're upserted, not versioned.

---

## How to add a new screen for a connected server

1. Extend `SshClient` (and `SftpSession` if file-related) with the new capability you need. Domain first.
2. Implement it in `features/ssh/data/`.
3. Create a feature module under `lib/features/<name>/`:
   - `domain/<name>_state.dart` — freezed-ish state class
   - `presentation/<name>_notifier.dart` — `StateNotifierProvider.family`
   - `presentation/<name>_screen.dart` — widget, `ConsumerStatefulWidget` if it needs lifecycle
4. Add the route in `app_router.dart` and a `_ActionTile` in `server_detail_screen.dart`.
5. Add unit tests under `test/`.
6. Run `flutter analyze` + `flutter test`.
7. Build for iOS simulator and launch: `flutter build ios --simulator --no-codesign && xcrun simctl install booted build/ios/iphonesimulator/Runner.app && xcrun simctl launch booted co.opspocket.opspocket`.

---

## Feature flagship tours

### SFTP browser (`lib/features/files/`)
- Opens one SFTP session per browser screen
- Path normalisation is pure (`domain/sftp_browser_state.dart` — `normalizeSftpPath`, `parentOf`, `breadcrumbsFor`)
- UI auto-starts an open on mount, auto-closes on dispose
- Upload uses `file_picker: ^8.1.2` — bytes first, fall back to `File.readAsBytes()` for large iOS picks
- Preview: UTF-8 first, Latin-1 fallback, hex dump if both fail or any NUL byte in first 4 KB

### Server health (`lib/features/server_health/`)
- One composite SSH command every 10 s — see `serverHealthProbeCommand`
- `ServerHealthParser` is pure and fully tested — extend by adding sections, not by touching the parser logic
- Tiles embedded in server detail only render when `SshConnectionState.connected`
- Full breakdown screen is `/servers/:id/health`

### The Bridge / MCP (`mission-control` repo, not this one)
The Bridge is an MCP endpoint inside the separate `mission-control` Next.js app (`https://github.com/findgriff/mission-control`). Claude connects to it to self-heal failing OpenClaw bots. The OpsPocket app interacts with Mission Control via the tunnel feature (`lib/features/tunnel/`), not directly via MCP.

### ClawGate (`lib/features/tunnel/`)
SSH direct-tcpip channel → local socket → WKWebView. **iOS SFSafariViewController suspends the Dart isolate and kills the tunnel** — must use `webview_flutter`. Start the accept loop *before* setting state active to avoid a race.

---

## Running locally

```bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs   # only if models changed
flutter run -d "iPhone 17"       # whatever simulator is booted
flutter test                     # full suite
flutter analyze lib              # lint the new code
```

If the app icon changed: `xcrun simctl uninstall booted co.opspocket.opspocket` first to clear the cache.

On a real device there's an iOS 26 ProMotion crash patched in `ios/Runner/AppDelegate.swift` — see HANDOVER.md § "iOS 26 ProMotion Crash Fix" for the reason. Don't remove that patch until Flutter ships an iOS 26-compiled engine.

---

## When you get stuck

- The answer is probably in `HANDOVER.md` under "Feature: X" sections
- If a piece of state isn't flowing, verify you're using the right provider family ID (always the server id string)
- If SSH is doing something weird, re-read `ssh_client_impl.dart` — the connect flow has a specific fingerprint-capture ordering that's easy to break
- Before claiming "it works," run `flutter analyze` and `flutter test` and inspect output. The test suite is small and fast.
