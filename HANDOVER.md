# OpsPocket — Project Handover

**Last updated:** 2026-04-17  
**App:** OpsPocket — mobile SSH/VPS management console (Flutter, iOS-first)  
**Bundle ID:** co.opspocket.opspocket  
**Flutter:** 3.41.7 / Dart 3.11.5

---

## What This App Does

OpsPocket lets a user connect to their VPS over SSH from iPhone and:
- Run terminal commands
- Use a slash-command palette with pre-built ops commands (systemd, Docker, PM2, tmux, OpenClaw)
- (Planned) Open the OpenClaw web UI through an SSH tunnel directly from the phone

---

## Architecture Overview

```
lib/
  app/           — router, theme, core utilities
  features/
    server_profiles/   — CRUD for saved SSH servers
    ssh/               — SSH connection (dartssh2 behind SshClient interface)
    terminal/          — interactive terminal screen
    command_templates/ — slash-command palette + builtin templates
    splash/            — logo splash screen (3s on launch)
    tunnel/            — (PLANNED) ClawGate SSH tunnel to browser
  shared/
    database/   — Drift (SQLite) schema + DAOs
    models/     — Freezed value types
    providers/  — shared Riverpod providers
    storage/    — flutter_secure_storage wrapper
```

Key libraries: `flutter_riverpod`, `dartssh2`, `drift`, `flutter_secure_storage`, `go_router`, `url_launcher` (pending).

---

## All Changes Made (Session Log)

### 1. Platform Setup
- Added iOS platform: `flutter create --platforms=ios .`
- Added web platform: `flutter create --platforms=web .`
- Downloaded iOS Simulator runtime (~8.39 GB via `xcodebuild -downloadPlatform iOS`)
- Ran code generation: `dart run build_runner build --delete-conflicting-outputs`

### 2. SSH Password Storage
**Problem:** App had no way to store or use a password — only key auth worked.

**Files changed:**
- `lib/shared/storage/secure_storage.dart` — added `SecretKeys.sshPassword(id)` key
- `lib/features/server_profiles/presentation/server_edit_screen.dart` — added password TextField; saves to Keychain on save
- `lib/features/ssh/presentation/ssh_connection_notifier.dart` — reads password from Keychain before connecting, passes to `SshCredentials`

### 3. Bug Fixes
- **NoSuchMethodError on `.name`** (`server_detail_screen.dart`): `_MetaCard` used `dynamic` for server param. Fixed to `final ServerProfile server`.
- **BoxConstraints infinite width crash**: `ElevatedButton` with `minimumSize: Size.fromHeight(52)` placed in `Row`. Fixed with `SizedBox(height: 44)`.
- **RenderMetaData layout errors**: `SelectableText` inside `ListView`. Replaced with `Text`.
- **New OpenClaw commands not appearing**: `seedBuiltinsIfEmpty()` only seeded on empty DB. Changed to always upsert all builtins.

### 4. UI Theme — OpsClaw Palette
**File:** `lib/app/theme/app_theme.dart` (complete rewrite)

| Token | Hex | Usage |
|---|---|---|
| `_red` | `#FF3B1F` | Buttons, accents |
| `_deepRed` | `#B81200` | Danger, depth |
| `_cyan` | `#00E6FF` | Connected state, tech accent |
| `_softRed` | `#FF6A4D` | Warnings, soft highlight |
| `_black` | `#000000` | Background |
| `_darkGray` | `#2A2A2A` | Cards, surfaces, inputs |
| `_lightText` | `#E6E6E6` | Primary text |
| `_muted` | `#8A93A1` | Secondary text |

### 5. JetBrains Mono Font
- Downloaded `JetBrainsMono-Regular.ttf` and `JetBrainsMono-Bold.ttf` → `assets/fonts/`
- Registered in `pubspec.yaml`
- `AppTheme.mono()` updated to use `fontFamily: 'JetBrainsMono'`, height 1.45, letterSpacing 0.3

### 6. Logo Splash Screen
- Copied `OpsPoket.png` → `assets/logo.png`
- Created `lib/features/splash/presentation/logo_splash_screen.dart` — black background, fade-in animation (600ms), 3-second hold, then navigates to main app
- `lib/app/router/app_router.dart` — added `/splash` route as `initialLocation`

### 7. Terminal Screen — Premium Redesign
**File:** `lib/features/terminal/presentation/terminal_screen.dart` (complete rewrite)

Key changes:
- Local palette: pure white output text (`#FFFFFF`), `#888888` muted
- JetBrains Mono throughout
- macOS-style traffic-light dots in AppBar (red/orange/cyan)
- `_EntryBlock`: left colour border, command line with `❯` prompt, timestamp, duration, exit code badge
- `_StatusBar`: pulsing dot showing SSH state, tap to reconnect
- Input bar: `❯` / `○` prompt symbol, borderless TextField, bolt (palette) + send (red glow) buttons
- Inline `/` suggestion dropdown via `Overlay` + `CompositedTransformTarget`/`CompositedTransformFollower`

### 8. OpenClaw CLI Commands
- `lib/shared/models/command_template.dart` — added `openclaw` to `CommandCategory` enum
- `lib/features/command_templates/data/builtin_templates.dart` — added 23 OpenClaw commands:
  - Gateway: status, start, restart, stop
  - Diagnostics: status, doctor, logs, logs --follow
  - Channels, cron (list/add/remove), skills (list/install)
  - Agents, tasks, models, config, backup, update
  - Systemd: status, restart, logs (journalctl)
- `lib/features/command_templates/presentation/slash_palette.dart` — added `'OpenClaw'` label for the category
- `lib/features/command_templates/data/command_template_repository_impl.dart` — `seedBuiltinsIfEmpty()` now always upserts all builtins (idempotent, stable IDs)

### 9. App Icon
- Generated all 15 required iOS icon sizes from `assets/logo.png` using `sips` (macOS built-in)
- Output to `ios/Runner/Assets.xcassets/AppIcon.appiconset/`
- Must uninstall app from simulator first to clear icon cache: `xcrun simctl uninstall <device> co.opspocket.opspocket`

---

## Feature: ClawGate (SSH Tunnel to Browser)

**Status:** Built and shipping (Clawbot + Mission Control).  
**Spec:** `docs/superpowers/specs/2026-04-17-clawgate-design.md`

### What was built

Adds a tunnel tile to the server detail screen supporting two destinations:

**Clawbot (port 18789):**
1. Runs `su - clawd -c '... openclaw dashboard --no-open'` over SSH and parses `#token=...` from stdout
2. Binds a local `ServerSocket` on `127.0.0.1:0`
3. Pipes TCP connections via SSH `direct-tcpip` to `127.0.0.1:18789` on VPS
4. Opens in-app WKWebView (`ClawGateWebViewScreen`) at `http://127.0.0.1:PORT/#token=TOKEN`

**Mission Control (Nginx port 80 → /mission-control):**
1. No token fetch — goes straight to tunnel setup
2. Same ServerSocket + direct-tcpip pipe to port 80
3. Opens animated loading screen (`MissionControlScreen`) then reveals WKWebView at `http://127.0.0.1:PORT/mission-control`

**Key implementation note:** iOS `SFSafariViewController` and external Safari both suspend the Dart isolate, killing the tunnel. `webview_flutter` (WKWebView) runs in-process and works correctly. The `_acceptLoop` is started *before* setting state to active to avoid a race condition where the WebView connects before the accept loop is ready.

### Files added/changed

| File | Change |
|---|---|
| `lib/features/ssh/domain/ssh_forward_channel.dart` | NEW — `SshForwardChannel` type (stream + sink) hiding dartssh2 |
| `lib/features/ssh/domain/ssh_client.dart` | Added `forwardChannel(host, port)` abstract method |
| `lib/features/ssh/data/ssh_client_impl.dart` | Implemented `forwardChannel` via `dartssh2` `forwardLocal()` |
| `lib/features/tunnel/domain/claw_gate_state.dart` | NEW — `ClawGateStatus`, `TunnelTarget` enums + `ClawGateState` |
| `lib/features/tunnel/presentation/claw_gate_notifier.dart` | NEW — `ClawGateNotifier` (StateNotifier) + `clawGateProvider` |
| `lib/features/tunnel/presentation/claw_gate_webview_screen.dart` | NEW — in-app WKWebView for Clawbot |
| `lib/features/tunnel/presentation/mission_control_screen.dart` | NEW — animated loading screen + WKWebView for Mission Control |
| `lib/features/server_profiles/presentation/server_detail_screen.dart` | Added `_ClawGateTile`, `_DestinationButtons`, `_TabButtons`; routes to correct screen per target |
| `assets/mission_control_logo.png` | NEW — Mission Control logo asset |
| `pubspec.yaml` | Added `url_launcher`, `webview_flutter`; registered `mission_control_logo.png` asset |

### Mission Control animation screen details
`mission_control_screen.dart` — three animation controllers:
- `_orbitCtrl` (2400ms, repeat) — rotates a 270° sweep-gradient arc around the logo
- `_pulseCtrl` (1600ms, repeat) — three concentric red rings pulsing outward with phase offsets 0/0.33/0.66
- `_revealCtrl` (600ms, one-shot) — crossfades loading overlay → WebView when `onPageFinished` fires

Status messages cycle every 1.4s while loading: "Establishing SSH tunnel…", "Handshaking with VPS…", "Routing to Mission Control…", "Loading interface…"

### Splash screen updates
- Delay changed from 3s to 4s
- Spin-on animation added: logo rotates in from 360° (easeOutCubic), scales up from 0.65 (easeOutBack), fades in
- iOS `LaunchScreen.storyboard` background changed from white to black (no white flash before splash)

---

## Feature: One-Tap Mission Control Deploy

**Status:** Shipping.

Adds a "Deploy Mission Control" tile to the server detail screen that runs 7 sequential SSH steps to install/update the Next.js Mission Control web app on the VPS.

### Steps executed
0. **Check VPS** — `test -d /home/clawd/mission-control` — detects first-run vs update
1. **Pull code** — first run: `git clone https://github.com/findgriff/mission-control.git`; update: `git fetch origin && git reset --hard origin/main` (handles divergent history)
2. **npm install** — full install (TypeScript is a devDependency required for build)
3. **npm run build** — 5-minute timeout
4. **Start service** — `which pm2 || npm install -g pm2` then `pm2 restart` or `pm2 start`
5. **pm2 save** — persists process list across reboots
6. **Nginx** — idempotent shell script: skip if already on port 3001, update port if wrong, insert proxy block if missing

### Files added/changed
| File | Change |
|---|---|
| `lib/features/mission_control/domain/deploy_state.dart` | NEW — `DeployStep`, `DeployState`, `DeployStepStatus` |
| `lib/features/mission_control/presentation/deploy_notifier.dart` | NEW — `DeployNotifier` + `deployProvider` |
| `lib/features/mission_control/presentation/deploy_screen.dart` | NEW — animated step-by-step deploy UI with retry + copy output |
| `lib/features/server_profiles/presentation/server_detail_screen.dart` | Added Deploy Mission Control tile |
| `test/deploy_notifier_test.dart` | NEW — 5 unit tests, all passing |

### Key constants
```dart
const _repo = 'https://github.com/findgriff/mission-control.git';
const _dir  = '/home/clawd/mission-control';
String _clawd(String cmd) =>
    """su - clawd -c 'export PATH="\$HOME/.npm-global/bin:/usr/local/bin:/usr/bin:\$PATH"; $cmd'""";
```

---

## Feature: OpenClaw UI Tunnel (Clawbot renamed)

**Status:** Shipping. "Clawbot" destination renamed to "OpenClaw UI" throughout.

### Changes from original ClawGate
- **Token source fixed** — reads `gateway.auth.token` directly via Python from `~/.openclaw/openclaw.json` (no CLI subcommand, which doesn't exist in this version)
- **New animated loading screen** — `lib/features/tunnel/presentation/openclaw_ui_screen.dart`: cyan pulsing rings + rotating arc + OpsPocket crab logo, identical structure to `MissionControlScreen`
- **Deleted** `lib/features/tunnel/presentation/claw_gate_webview_screen.dart` (replaced)
- **Asset added** — `assets/openclaw_ui_logo.png`
- `lib/features/tunnel/domain/claw_gate_state.dart` — `TunnelTarget.clawbot` label changed to `'OpenClaw UI'`

---

## Feature: Quick Actions (Premium Redesign)

**Status:** Shipping. Quick Actions tile restored on server detail screen.

### What's there
9 default actions seeded on first run, 5 OpenClaw-specific ones upserted on every launch (stable IDs, no duplicates):

| ID | Label | Template |
|---|---|---|
| `qa.status` | VPS Status | `builtin.generic.status` |
| `qa.restart_service` | Restart service | `builtin.systemd.restart` |
| `qa.pm2_restart` | PM2 restart | `builtin.pm2.restart` |
| `qa.reboot` | Reboot server | `builtin.server.reboot` |
| `qa.oc.gateway_restart` | OC Gateway restart | `builtin.openclaw.gateway-restart` |
| `qa.oc.gateway_status` | OC Gateway status | `builtin.openclaw.gateway-status` |
| `qa.oc.pm2_mc` | Mission Control PM2 | `builtin.pm2.list` |
| `qa.oc.nginx_restart` | Nginx restart | `builtin.nginx.restart` |
| `qa.oc.doctor` | OpenClaw doctor | `builtin.openclaw.doctor` |

### Design
- Dark `#111111` cards, icon in colour-coded rounded container
- Icon mapped from `templateId` via `_metaByTemplate` lookup in `quick_actions_screen.dart`
- Category chip (`OPENCLAW`, `PM2`, `NGINX`, `DANGER`, etc.) below label
- Animated press (scale 0.95 + colour glow)
- Output sheet: dark bottom sheet, monospace output, copy button

### New builtin templates added
- `builtin.nginx.restart` — `sudo systemctl restart nginx && sudo systemctl status nginx --no-pager`
- `builtin.nginx.status` — `sudo systemctl status nginx --no-pager`

---

## Screen inventory (server detail)

Current tiles shown on `/servers/:id`:
1. **Connection banner** — SSH status indicator
2. **Server meta card** — host, user, auth method, tags
3. **Quick Actions** → `/servers/:id/quick-actions`
4. **Terminal** → `/servers/:id/terminal`
5. **Deploy Mission Control** → `DeployScreen` (fullscreen dialog)
6. **Tunnel (ClawGate)** — inline tile with OpenClaw UI + Mission Control pills
7. **SSH connect/disconnect** buttons

Intentionally hidden (commented out, not deleted): Logs, native Mission Control screen (use Tunnel → Mission for live data instead).

---

## Key Environment Notes

- SSH connects via `dartssh2` behind a `SshClient` interface (`lib/features/ssh/domain/ssh_client.dart`)
- Passwords stored in iOS Keychain via `flutter_secure_storage` (key: `ssh.pwd.<serverId>`)
- Private keys stored in Keychain (key: `ssh.pk.<serverId>`)
- Database: Drift SQLite at app documents path
- State management: Riverpod (`StateNotifierProvider.family` for per-server providers)

---

## Running the App

```bash
# Install dependencies
flutter pub get

# Regenerate code (if models changed)
dart run build_runner build --delete-conflicting-outputs

# Run on simulator
flutter run -d "iPhone 16"

# To clear icon cache after icon changes:
xcrun simctl uninstall booted co.opspocket.opspocket
flutter run
```
