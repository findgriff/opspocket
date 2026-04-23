> **⚠ REPO SCOPE — 2026-04-23**
>
> This is the **OpsPocket iPhone app** repo (Flutter/iOS). The SaaS
> platform (backend, marketing site, admin panel, tenant installer) was
> split out to a separate repo: <https://github.com/findgriff/opspocket-platform>.
>
> Sections below that refer to dev-box operations, Caddy, Stripe, Hetzner
> API, customer dashboards, /admin, /account, or `infra/backend/*` are
> out of scope here — look for them in the platform repo. Everything
> about the Flutter app, Xcode, iOS device install, Keychain, SSH
> client interface, and `lib/features/*` is still canonical here.

---

# HANDOVER — OpsPocket iPhone App + Platform

**Last updated:** 2026-04-23
**Last session owner:** Claude (Lead DevOps / SaaS Platform Engineer role)
**Primary product this document focuses on:** OpsPocket iPhone app (Flutter)
**Secondary:** OpsPocket Cloud platform — just enough context for a new agent to not break it

This document is the single source of truth for project state. A new agent should read **this file first**, then `CLAUDE.md`, then start work.

**Accuracy contract used throughout this file:**

- ✅ **Verified** — directly observed or ran the command this session
- 🟡 **Likely** — stated consistently across prior sessions but not re-verified today
- ❓ **Unknown** — must be checked before relying on it

---

## 1. Project overview

OpsPocket is two products under one brand, in one git repo:

- **OpsPocket iPhone app** — Flutter/iOS mobile client. SSH + web-tunnel + quick actions for managing a VPS from your phone. Bundle ID `co.opspocket.opspocket`. Shelved for public release; usable as a tech demo on the founder's own iPhone.
- **OpsPocket Cloud** — SaaS that provisions a dedicated Hetzner VPS per customer, installs OpenClaw via `install-openclaw.sh`, emails credentials, and exposes a customer dashboard + admin CRM at `opspocket.com`. Billing via Stripe (live). Not yet generating revenue but is technically ready for a first real sale.

The iPhone app and the Cloud platform are independent — the app works against any SSH-accessible box with OpenClaw installed, not just Cloud tenants.

---

## 2. Current status — iPhone app

### Verified state on 2026-04-23

- App **builds cleanly in release mode** after clearing xattrs on the project dir (known macOS issue — see §7).
- App **installs on physical iPhone** via `xcrun devicectl device install app` — bypasses Flutter's flaky wireless installer.
- App **launches and reaches the server list** after the user trusts the dev cert once (Settings → General → VPN & Device Management).
- App **SSH-connects** successfully as user `apptest` on the dev box (password auth) — verified terminal returns `hostname` = `opspocket-dev`.
- **Server Health tiles** (CPU / RAM / Disk / Uptime) populate live from `/proc` after SSH connects.
- **ClawGate tunnel** to OpenClaw UI is **working** — user confirmed: "the openclaw UI works".
- **Mission Control** via ClawGate tunnel works in the same way (same backend, same auth).
- **97 → 85 → 79 → current tests pass** (count has fluctuated as features were deleted/added; see §6).

### What the app currently shows (verified layout on physical device)

Running on Craig's iPhone 14 Pro Max, iOS 26.4.1:

1. Splash (logo animation, ~4 s)
2. Server list
3. Server detail screen with:
   - SSH: connected banner
   - Server Health card (CPU / RAM / Disk / Uptime tiles, live)
   - Quick Actions tile
   - Terminal tile
   - Mission Control card with Update button (routes to DeployScreen)
   - Tunnel pill row (OpenClaw UI + Mission destinations)
   - SSH Connect / Disconnect buttons

Files (SFTP) tile is NOT currently in the layout — the underlying WIP module was deleted on 2026-04-23 when it blocked the release build (see §4).

---

## 3. Completed

### Features shipped in the app

- SSH connect / disconnect with password + private-key auth; credentials stored in iOS Keychain (accessibility: `first_unlock_this_device`)
- Terminal screen with slash-command palette (40+ builtins: systemd, Docker, PM2, tmux, nginx, OpenClaw CLI)
- Quick Actions grid (one-tap commands)
- Server Health tiles (live CPU / RAM / disk / uptime from `/proc`)
- Logs screen (journald/docker/PM2 tails)
- Audit log
- Biometric unlock on relaunch (local_auth)
- ClawGate SSH-tunnel to WebView
  - Two destinations: **OpenClaw UI** and **Mission Control** — both tunnel to the OpenClaw daemon on `127.0.0.1:18789` (unified 2026-04-23)
  - Handles `gateway.auth.mode = "none"` (basic-auth via Caddy) — token fetch tolerated as optional
  - WebView shows a basic-auth prompt; customer types `clawmine` password
- Mission Control credential wiring in server profile:
  - Optional OpenClaw host override (falls back to SSH host)
  - clawmine password, both stored in Keychain under `SecretKeys.clawmineHost(<id>)` and `SecretKeys.clawminePassword(<id>)`
- Deploy Mission Control flow (`DeployScreen` + `deploy_notifier`) — SSH-driven git clone + rebuild
- Builtin template system + Drift (SQLite) persistence for user-added templates

### Infrastructure completed

- Full OpsPocket Cloud SaaS platform — Stripe live, Hetzner provisioning, Resend email, Caddy TLS multi-site. See §15 for a brief overview.
- Customer dashboard at `opspocket.com/account` (magic-link auth)
- Admin CRM at `opspocket.com/admin` (Caddy basic_auth)
- Device pairing deep-link flow (`opspocket://pair?code=…`) — backend generates + stores; app side needs Info.plist URL scheme + pair handler (not yet built, see §5)

### Verified decisions from prior sessions

- Native Mission Control screen (`mc_screen.dart` + tabs + SSH-backed `mc_repository`) was **deleted** on 2026-04-23. Mission Control is now a tunneled WebView of OpenClaw's own Control UI. Rationale in commit `2bf2934`.
- Legacy nginx `/mission-control` path is abandoned — both `TunnelTarget.clawbot` and `TunnelTarget.missionControl` point to `127.0.0.1:18789`.
- iOS app is **shelved for public release** — user decided this session. The Flutter code stays in-repo; Cloud is the near-term revenue product.
- Cloud sticks with **per-VPS-per-customer** model. Shared-host Docker pivot is deferred until 5+ paying customers.

---

## 4. Partially completed

### SFTP / Files feature — **DO NOT re-enable as-is**

- Files present in prior commits: `lib/features/files/*`, `lib/features/ssh/domain/sftp_session.dart`, `lib/features/ssh/data/sftp_session_impl.dart`, `test/sftp_path_test.dart`
- **Deleted on 2026-04-23** (commit `f334c92`) because they blocked the release build with three Dart errors:
  1. `lib/features/files/presentation/sftp_browser_screen.dart:3` — `package:file_picker/file_picker.dart` not in `pubspec.yaml`
  2. `lib/features/files/presentation/sftp_browser_screen.dart:285` — `FilePicker` getter undefined
  3. `lib/features/files/presentation/sftp_notifier.dart:36` — `SshClient.openSftp()` method does not exist on the interface
- To complete: add `file_picker` to `pubspec.yaml`, implement `sftp()` or `openSftp()` on `SshClient` (`lib/features/ssh/domain/ssh_client.dart`) + `SshClientImpl`, restore deleted files from commit predating `f334c92` (they were uncommitted until then — history starts with commit that added them to Git, so check git log carefully), re-add Files tile to `server_detail_screen.dart`, re-add `/files` route to `app_router.dart`.

### App-side pairing handler — **backend ready, app side stub**

- Backend emits `opspocket://pair?code=<code>` in welcome emails. Single-use, 7-day TTL, full tenant creds in the payload.
- App needs (all unbuilt):
  - URL scheme registered in `ios/Runner/Info.plist` (`CFBundleURLTypes` → scheme `opspocket`)
  - Deep-link handler screen in Flutter (`lib/features/pairing/`)
  - Fetch `/api/pair/<code>` → write server profile + Keychain entries → show success
- Design: fetch once, never store the code, write `clawmine.pwd.<id>` + `clawmine.host.<id>` + SSH creds to Keychain, then route to `/servers/<id>`.
- Server-side also supports web fallback at `https://opspocket.com/pair?code=…` which shows credentials in a one-shot web page (already live).

### Mission Control UI polish

- Feature works; UI could be better. Loading/error states in the WebView are minimal. No tool-call telemetry panel. Acceptable for v1, not for a polished public release.

---

## 5. Known issues / broken / fragile

### iOS 26 wireless debug install hangs black

- `flutter run --debug --device-id <UDID>` over WiFi installs the app but the app sits on a black screen forever.
- **Root cause:** Flutter debug builds include a stub that waits on the Dart VM service. Over WiFi on iOS 26 the handshake is flaky; when it fails, `runApp()` never fires.
- **Workarounds (both verified working this session):**
  1. Use **release mode** (`flutter build ios --release` + `xcrun devicectl device install app build/ios/iphoneos/Runner.app`) — has no VM service dependency
  2. Use **a cable** for debug-mode development

### macOS xattr breaks `flutter build ios`

- `~/Downloads/` inherits `com.apple.FinderInfo` / `com.apple.provenance` / `com.apple.macl` extended attributes on macOS 15+
- Flutter's `xcode_backend.sh` script fails at the "Thin Binary" / "Run Script" phase with opaque error: `Failed to package <project-dir>`
- **Fix:** `cd <project dir> && xattr -cr .` before every release build (safe to re-run)

### DEVELOPMENT_TEAM not in `project.pbxproj`

- Default `ios/Runner.xcodeproj/project.pbxproj` has `CODE_SIGN_STYLE = Automatic` but no `DEVELOPMENT_TEAM`
- Flutter's codesigning fails silently without it
- **Fix applied this session** — injected `DEVELOPMENT_TEAM = RT2UR47KNW;` after each `CODE_SIGN_STYLE = Automatic;` line. Commit may or may not include this edit — re-verify with `grep -n "DEVELOPMENT_TEAM" ios/Runner.xcodeproj/project.pbxproj`. If missing, re-apply.

### Dev cert re-trust required after every clean reinstall

- `xcrun devicectl device install app` onto a clean-slate iPhone (or after `uninstall` + `install`) requires the user to tap
  **iPhone Settings → General → VPN & Device Management → Apple Development: findgriff@gmail.com → Trust**
- Then tap the app icon. Normal Apple developer cert UX.

### `flutter run` can't install over wireless on iOS 26

- Both `--debug` and `--release` variants fail at the install step with generic "Error running application"
- **Workaround:** split build and install: `flutter build ios --release`, then `xcrun devicectl device install app build/ios/iphoneos/Runner.app`. Works 100% of the time this session.

### Test count has fluctuated

- 97 → 85 → 79 across the day as features were deleted and restored. Current **79/79 passing** ✅ on main.

### CI `installer-ci` GitHub Actions workflow fails

- Pre-existing systemd-in-Docker fidelity issue — OpenClaw user-service doesn't start inside a privileged Ubuntu container.
- Real `infra/test-installer.sh` against a Hetzner VM passes.
- Not blocking app development. Fix options documented in `HANDOVER` history: soft-fail gateway check under `CI_ENV=1`, switch to machinectl image, or replace with on-tag Hetzner integration test.

### Flutter lint info-level items

- 66 `info`-level lints (trailing commas, `use_build_context_synchronously`, one `unawaited_futures`). Zero errors, zero warnings. Cosmetic only.

### Welcome email deliverability unverified at scale

- Resend domain `mail.opspocket.com` verified, one test send successfully delivered (`last_event: delivered`) on 2026-04-22 per prior log.
- Spam reputation still building; keep an eye on customer inbox placement once real purchases land.

---

## 6. What has been tested

### Unit + widget tests (on `main`)

- **79 tests pass** as of commit `40ace12` (ran `flutter test` this session). Covers:
  - Command template builtins (`builtin_templates_test.dart`)
  - ClawGateState transitions (`claw_gate_state_test.dart`)
  - MC bridge URL provider edge cases (`mc_bridge_url_provider_test.dart`, 10 tests)
  - MC bridge client JSON-RPC (`mc_bridge_client_test.dart`)
  - Danger-command detector (`danger_detector_test.dart`)
  - Mission Control tabs widget (if still present; verify `test/` contents)
  - Placeholder utils, sanitizer, secure storage fake, repositories, deploy notifier

### End-to-end (manual, on physical iPhone today)

- Splash renders + routes to server list ✅
- Profile load + save (with Mission Control section) ✅
- SSH connect as `apptest` ✅
- Terminal returns `hostname` ✅
- Server Health tiles go live ✅
- ClawGate → OpenClaw UI tunnel → basic-auth dialog → dashboard loads ✅ (user confirmed)
- Mission Control tile opens DeployScreen ✅

### Not yet tested

- SFTP / Files (deleted)
- Pairing deep-link (app handler unbuilt)
- Real production-path workflow: Stripe purchase → Hetzner VPS → welcome email → pair button → app auto-configured (needs both Stripe live-card smoke-test AND app pairing handler to exist)

---

## 7. What still needs building

### High priority

1. **Pairing deep-link handler in app** (~1 day)
   - Register `opspocket://` URL scheme in `ios/Runner/Info.plist`
   - Add Universal Link config (`.well-known/apple-app-site-association` on opspocket.com — not yet created)
   - Build `PairingScreen` that fetches `/api/pair/<code>`, writes server profile + Keychain, navigates to detail
   - Without this, customers must paste creds manually — defeats the whole pairing flow

2. **Restore SFTP / Files feature** (~0.5 day)
   - Add `file_picker` to `pubspec.yaml`
   - Implement `SftpSession` / `openSftp()` or equivalent on `SshClient`
   - Restore deleted files from git history (see §4 for paths)
   - Re-wire route + tile

### Medium priority

3. **Mission Control loading/error UX** — WebView loading spinner, auth-failure toast, retry button
4. **App Store readiness** — privacy manifest, App Tracking Transparency prompts if we add analytics, screenshots
5. **Universal Link domain verification** (associated with `opspocket://` pairing)
6. **SSH key import** — currently users paste the key body into a text field; pasting from `~/.ssh/id_ed25519` is fiddly on iPhone. Explore iCloud Keychain sync or a "share sheet" entry.

### Low priority / phase 2

7. Sign-in with Apple for customer accounts (currently magic-link email only)
8. Push notifications for long-running commands
9. iPad split-screen / Mac Catalyst target
10. Android Flutter build

See also: the Cloud/CRM platform has its own backlog — see §15.

---

## 8. Current priorities

In execution order, assuming the goal is **public-ready iPhone app that pairs with a Cloud tenant in one tap**:

1. ⚠️ **Run a real £15.99 Starter purchase** on `opspocket.com/cloud` (not app-blocking but validates Cloud pipeline which the app depends on for pairing)
2. 🎯 **Build the pairing deep-link handler in the app** (§7.1)
3. 🎯 **Restore SFTP/Files** (§7.2) — only if we want it in v1
4. 🧪 **Ship to TestFlight** so a small group of beta users can try it
5. 🎨 **Mission Control WebView polish** (§7.3)

Everything beyond these is phase-2.

---

## 9. Architecture overview

### App stack (✅ verified from `pubspec.yaml`)

- **Flutter** 3.41.7 (stable)
- **Dart** 3.11.5
- **State:** Riverpod 2.6.1 (`StateNotifierProvider.family` for per-server state)
- **Routing:** go_router 14.8.1
- **SSH:** dartssh2 — hidden behind `SshClient` / `SshClientImpl` interfaces; **feature code never imports dartssh2 directly**
- **Database:** Drift 2.x on SQLite — regenerate with `dart run build_runner build --delete-conflicting-outputs` after schema changes
- **Secrets:** flutter_secure_storage 9.2.4 → iOS Keychain (`first_unlock_this_device`)
- **Biometric:** local_auth 2.3.0
- **HTTP:** dio 5.x (for MCP JSON-RPC and future API calls)
- **WebView:** webview_flutter (with webview_flutter_wkwebview on iOS)

### Feature modules (`lib/features/`)

```
audit/              — command audit log
auth_security/      — biometric unlock gate
command_templates/  — slash palette + 40+ builtins
logs/               — journald/docker/PM2 tails
mission_control/    — DeployScreen + deploy_notifier (re-install OpenClaw from app)
                      (mc_screen + mc_repository + mc_models DELETED 2026-04-23)
                      mc_bridge_client.dart still there for future in-app MCP tool calls
quick_actions/      — tile-based one-tap commands
server_health/      — live CPU/RAM/disk/uptime via /proc + ssh
server_profiles/    — CRUD + detail screen (current main surface)
settings/
splash/             — logo splash
ssh/                — SshClient domain + dartssh2 impl + connection notifier
terminal/           — interactive terminal screen
tunnel/             — ClawGate state + notifier + WebView screens
```

### Shared code (`lib/shared/`)

```
database/           — Drift schema + generated code
models/             — plain value types (ServerProfile, etc.)
providers/          — cross-feature Riverpod
storage/            — secure_storage wrapper + SecretKeys class
```

### Key files a new agent will touch

✅ verified paths:

| File | Purpose |
|---|---|
| `lib/main.dart` | `runApp(ProviderScope(child: OpsPocketApp()))` |
| `lib/app/router/app_router.dart` | All routes — splash, servers, terminal, quick-actions, logs, health |
| `lib/app/theme/app_theme.dart` | OpsClaw palette (red/black/cyan), JetBrains Mono, all component themes |
| `lib/features/server_profiles/presentation/server_detail_screen.dart` | The main per-server hub (rebuilt 2026-04-23) |
| `lib/features/server_profiles/presentation/server_edit_screen.dart` | Add/edit form incl. Mission Control section (Keychain-only, no DB migration) |
| `lib/features/ssh/domain/ssh_client.dart` | **Canonical SSH interface — add methods here first** |
| `lib/features/ssh/data/ssh_client_impl.dart` | dartssh2 adapter |
| `lib/features/tunnel/domain/claw_gate_state.dart` | TunnelTarget + state model |
| `lib/features/tunnel/presentation/claw_gate_notifier.dart` | Binds local port, forwards via SSH channel |
| `lib/features/mission_control/data/mc_bridge_client.dart` | MCP JSON-RPC client + URL / auth providers |
| `lib/shared/storage/secure_storage.dart` | **Keychain key constants (SecretKeys class) — never typo** |
| `pubspec.yaml` | Dependencies + asset registration |

---

## 10. Key app flows

### 10.1 Cold start → server list

`main.dart` → `OpsPocketApp` → router initial route `/splash` (LogoSplashScreen, 4-sec hold) → `/` (SplashUnlockScreen, biometric) → `/servers` (ServerListScreen).

### 10.2 Add server profile

`/servers/add` → `ServerEditScreen` with fields: nickname, host/IP, port, username, auth method (private key / password), tags, notes, provider dropdown. Expandable **Mission Control (OpenClaw)** section has two Keychain-only fields: host override + clawmine password. On save, private key + ssh password + clawmine host + clawmine password write to Keychain under `SecretKeys.*(<serverId>)`.

### 10.3 SSH connect

`/servers/:id` → `_ConnectionBanner` + Connect button → `sshConnectionProvider(serverId).notifier.connect()` → reads Keychain → `SshClient.connect(...)` → banner turns cyan. Session state in `SessionState` model.

### 10.4 Terminal

`/servers/:id/terminal` → `TerminalScreen` → `CommandRunner` → `SshClient.exec(...)`. Slash key (`/`) → `SlashPalette` with all `builtin_templates.dart` plus user-saved templates from Drift.

### 10.5 ClawGate tunnel

Tile `_ClawGateTile` → `clawGateProvider(serverId).notifier.start(TunnelTarget.clawbot | missionControl)` →
1. Try to SSH-exec `_tokenCommand` (optional; 2026.4.5 doesn't use it)
2. `ServerSocket.bind(loopback, 0)` — local random port
3. Each inbound socket → `SshClient.forwardChannel('127.0.0.1', 18789)` — pipe both ways
4. Set `tunnelUrl = 'http://127.0.0.1:<port>/'` (or `/#token=<tok>` when token present)
5. User taps Open → `OpenClawUiScreen` or `MissionControlScreen` (WebView) loads URL
6. Caddy-fronted boxes prompt for basic-auth inside the WebView — customer types clawmine password

### 10.6 Mission Control (NEW architecture)

No longer a native tab stack. It's just ClawGate with `activeTarget = TunnelTarget.missionControl`. Lands at the same `127.0.0.1:18789/` as OpenClaw UI — same page, same auth. On legacy boxes with nginx-served `/mission-control`, both targets would work the same way (that path is gone in 2026.4.5).

### 10.7 Deploy / Update Mission Control

Purple "Mission Control" card with "Update" button on server detail → `DeployScreen` → 7-step SSH-driven pipeline (check VPS, clone repo, npm install, build, PM2, nginx, verify). `deploy_notifier.dart` runs `su - clawd -c '<cmd>'` via SSH. Only useful for legacy / BYO-VPS customers; 2026.4.5 Cloud tenants have MC pre-installed by `install-openclaw.sh`.

---

## 11. Environments in use

### Local development (Mac)

- **Host machine:** macOS 26.3.1 (verified this session via `sw_vers` / Xcode output)
- **Project path:** `/Users/findgriff/Downloads/opspocket-main` ✅ verified
- **Tooling verified:** Flutter 3.41.7, Dart 3.11.5, Xcode 26.2 (build 17C52)
- **Flutter channel:** stable
- **Brew-installed tooling likely present:** git, gh (GitHub CLI), rsync, sshpass — verify with `which` before relying on them
- **Project dir has macOS xattrs** — always `xattr -cr .` before release builds

### Physical iPhone (test device)

- **Craig's iPhone 14 Pro Max**, iOS 26.4.1 ✅
- **UDID:** `00008120-001A41693682201E` (Flutter device-id) ✅
- **Core Device UUID:** `3F2D242C-9CAB-5374-998F-E6BD5D2DF79A` (devicectl device-id) ✅
- **Paired wirelessly** — Xcode shows it under device dropdown; `xcrun devicectl list devices` confirms
- **Developer mode:** on ✅ (install works)
- **Dev cert trusted:** needs re-trust after each clean reinstall (see §5)

### Apple Developer

- **Team ID:** `RT2UR47KNW` ✅ verified via Xcode logs
- **Account email:** `findgriff@gmail.com` 🟡 (inferred from Xcode + elsewhere; likely correct)
- **Signing:** Automatic (`CODE_SIGN_STYLE = Automatic`)
- **TestFlight:** ❓ never set up as far as I know this session — verify in App Store Connect

### Dev box (cloud)

- **Hostname:** `opspocket-dev` ✅
- **Location:** Hetzner CX43, Nuremberg `nbg1` 🟡 per HANDOVER history
- **Public IP:** `178.104.242.211` ✅ verified via SSH this session
- **OS:** Ubuntu 24.04 🟡 per HANDOVER history
- **SSH shortcut:** `ssh dev` (configured in `~/.ssh/config` on Craig's Mac) ✅ used all session
- **Purpose:** Serves `opspocket.com` + runs the Cloud platform (Caddy, Python backend, email, orchestrator). Also doubles as a tenant-testbed for the app.

### Dev box's OpenClaw (app's test target)

- **URL:** `https://claw.dev.opspocket.com/` ✅ (TLS via Caddy DNS-01)
- **Username:** `clawmine` ✅
- **Password:** stored on dev box at `/root/CREDENTIALS.json` — do **not** include in git
- **MCP endpoint:** `https://claw.dev.opspocket.com/mcp`
- **Gateway token mode:** `gateway.auth.mode = "none"` in 2026.4.5; Caddy basic_auth is the gate
- **OpenClaw version:** 2026.4.5 ✅

---

## 12. Deployment / build workflow

### Local dev cycle

```bash
cd /Users/findgriff/Downloads/opspocket-main

# Fresh checkout / after pulling
flutter pub get
dart run build_runner build --delete-conflicting-outputs

# Run on simulator (iPhone 17 etc.)
flutter run -d "iPhone 16"

# Run on physical device (wireless) — DEBUG often hangs black on iOS 26.
# Cable works fine. Or use the release install below.
```

### Release-install to physical iPhone (known-working)

```bash
cd /Users/findgriff/Downloads/opspocket-main
xattr -cr .                                                # clear macOS finder xattrs
flutter build ios --release                                # ~30 s incremental; 2-3 min cold
DEV=3F2D242C-9CAB-5374-998F-E6BD5D2DF79A
xcrun devicectl device install app --device $DEV build/ios/iphoneos/Runner.app
sleep 3
xcrun devicectl device process launch --device $DEV co.opspocket.opspocket
```

Then on the iPhone, trust the dev cert once (Settings → General → VPN & Device Management).

### Tests

```bash
flutter analyze                                            # must be 0 errors, 0 warnings
flutter test                                               # 79/79 passing as of commit 40ace12
```

### Commit + push

```bash
git add <files>
git commit -m "..."                                        # see existing commit style
git push origin main
```

---

## 13. Dev setup requirements

For a new agent to become productive, they need:

1. macOS Sonoma+ (15+) with Xcode 26.x installed
2. Flutter 3.41.7 via brew or manual install
3. Apple Developer account added to Xcode with Team ID `RT2UR47KNW`
4. Craig's iPhone paired with Mac (wireless pairing works)
5. SSH access to the dev box — `ssh dev` should just work on Craig's Mac; a new agent running on a different Mac needs the private key added to `~/.ssh/config` pointing at `178.104.242.211`
6. GitHub CLI (`gh`) authenticated as `findgriff`
7. Clone: `git clone git@github.com:findgriff/opspocket.git`

---

## 14. Key decisions + assumptions

Decisions made that a new agent should **respect unless there is a strong reason**:

- **No pip deps on the Cloud backend** — Python stdlib only. `infra/backend/app.py`, `api_extras.py`, `sync_stripe.py`, `sync_hetzner.py` all use only `urllib`, `sqlite3`, `hmac`, `http.server`. This was deliberate — zero-install systemd service.
- **Per-VPS-per-customer** Cloud architecture stays until 5+ paying customers. Shared-host Docker pivot is a future optimization, not a blocker.
- **iOS app is shelved for public release** — keep in repo, don't delete; will re-enable once Cloud has paying customers.
- **SSH must go through `SshClient` interface** — never import `dartssh2` from feature code.
- **Builtin template IDs are stable** — never change an existing `builtin.*` ID; it would duplicate entries in users' local DBs.
- **Keychain access level is `first_unlock_this_device`** — don't change without auditing every Keychain caller; breaks background Face ID flows.
- **OpsClaw palette** — red `#FF3B1F`, cyan `#00E6FF`, near-black `#0A0A0B`. Always use `AppTheme.*` constants, never hardcode.
- **MC native reskin is gone — do not rebuild it.** Mission Control is a tunneled WebView of OpenClaw's own UI. Re-implementing is explicitly wrong.

---

## 15. Cloud / hosting context (brief — app depends on this for pairing)

This is the *secondary product* but the iPhone app's pairing flow depends on it. A new agent touching the app does NOT need to understand this deeply, but should know:

### What's live at opspocket.com

- `/` — public marketing homepage with scrolling announcement ticker
- `/cloud` — pricing page with 3 tiers + Stripe Payment Links (LIVE MODE)
- `/account` — customer dashboard (magic-link auth)
- `/admin` — internal CRM (Caddy basic_auth)
- `/pair` — deep-link fallback for pairing
- `/support`, `/blog`, status page at `status.opspocket.com`

### Backend service

- `opspocket-backend.service` (systemd unit, Python stdlib) on `127.0.0.1:8092`
- Handles Stripe webhook, customer account API, admin API, pairing API, Hetzner orchestrator
- Code: `infra/backend/app.py` + `api_extras.py` + `sync_stripe.py` + `sync_hetzner.py`
- DB: SQLite at `/var/lib/opspocket/tenants.db`

### What an iPhone app agent might need to touch

- `/api/pair/<code>` — returns `{tenant_id, host, mcp_endpoint, username, password, gateway_token, ssh_host, ssh_port, tier}` JSON — this is the payload the pairing handler consumes
- Web fallback `https://opspocket.com/pair?code=…` is a reference implementation for what the app should display

**If a new agent needs to modify backend code:** Cloud-specific docs are in prior HANDOVER revisions visible via git log. Ask before making backend changes.

---

## 16. SSH / Keychain / auth implementation notes

- **SSH private key**: stored as secret under `SecretKeys.sshPrivateKey(serverId)` → `ssh.key.<id>`. Written on profile save; read at connect time. Body is PEM (starts with `-----BEGIN OPENSSH PRIVATE KEY-----`).
- **SSH passphrase**: `SecretKeys.sshKeyPassphrase(serverId)` → `ssh.pass.<id>`. Optional.
- **SSH password**: `SecretKeys.sshPassword(serverId)` → `ssh.pwd.<id>`. Only used when `authMethod == passwordNotStored` — despite the name, the current implementation *does* store it.
- **OpenClaw host override**: `SecretKeys.clawmineHost(serverId)` → `clawmine.host.<id>`. Optional; if unset, `mcBridgeUrlProvider` falls back to the SSH host.
- **clawmine basic-auth password**: `SecretKeys.clawminePassword(serverId)` → `clawmine.pwd.<id>`. Equivalent to the legacy top-level `clawmineSecretKey(serverId)` function in `mc_bridge_client.dart`.
- **Provider API tokens**: `SecretKeys.providerToken(serverId)` → `provider.token.<id>`. For Hetzner/DO etc. if the user wires cloud API access.

All secrets are wiped when a profile is deleted (see `server_edit_screen.dart` `_confirmDelete`).

**Do not** read Keychain in `initState()` of any screen; it's async. Always use the Riverpod secureStorageProvider + await.

---

## 17. Repos / branches / recent commits

### Repo

- **GitHub URL:** `git@github.com:findgriff/opspocket.git` ✅ verified this session
- **Owner:** `findgriff`
- **Visibility:** ❓ (not verified — likely private)

### Branches

✅ Only branches seen this session:
- `main` (local + `origin/main`)
- `origin/HEAD -> origin/main`

No feature branches active. Work has been landing directly on `main` this week.

### Recent commits (oldest → newest, last 20 on `main` as of 2026-04-23)

| SHA | Subject |
|---|---|
| `40ace12` | feat(crm): full SaaS CRM v2 — Stripe+Hetzner sync, tenant drawer, analytics |
| `e87050e` | fix(site): move announcement ticker to sit directly under the nav |
| `e3877eb` | fix(site): ticker is now a single flowing announcement, not bullet list |
| `ae4f231` | feat(site): rewrite homepage ticker — Cloud-now vs App-soon split |
| `e794a2f` | feat(saas): ship customer dashboard, admin panel, and pairing flow |
| `f334c92` | restore(server-detail): rebuild the screenshot layout — live health + MC update card |
| `2bf2934` | refactor(mission-control): delete native reskin, tunnel to server-side UI |
| `bb215ad` | feat(mission-control): wire OpenClaw gateway credentials into server profile |
| `6f0dfd3` | feat(email): wire Resend as live SMTP relay — end-to-end verified |
| `b33bd35` | feat(site): add /support page required by Stripe live activation |
| `2ca4fbc` | feat(cloud): flip to live Stripe — 3 products, 6 prices, 6 Payment Links |
| `f38bb23` | chore(audit): Lead DevOps audit pass 2026-04-22 |
| `d4ad026` | fix(installer+orchestrator): code-server non-fatal + cloud-init marker integrity |
| `517c2f6` | fix(backend): inject dev-box SSH pubkey into tenant cloud-init |
| `4838658` | fix(backend): Hetzner label sanitisation + SSH key name + Postfix+DKIM |
| `d207c4c` | fix(installer): preserve multi-site Caddyfile + actually delete old site/ |
| `0c26a2f` | test(tunnel): add ClawGateState unit tests |
| `24d43b0` | feat(mission_control): rewire MCP client for OpenClaw 2026.4.5 gateway |
| `114ff5b` | test(mission_control): widget test for bottom-tab highlight + body swap |
| `7fd2061` | fix(mission_control): harden model parsing against non-int numeric fields |

The 3 most important for an app-focused agent: **`f334c92`, `2bf2934`, `bb215ad`** — they rewrite the server-detail layout, delete the native MC screen, and wire the MC Keychain creds respectively.

---

## 18. What to verify first in a new session

Run these **before writing any code** — any failure signals an environment issue to fix first:

```bash
# 1. Repo clean
cd /Users/findgriff/Downloads/opspocket-main
git status                                 # expect: clean or known untracked
git log -1 --oneline                       # expect: 40ace12 ... (or later)

# 2. Flutter toolchain
flutter --version                          # expect: 3.41.7, Dart 3.11.5
xcodebuild -version                        # expect: Xcode 26.x

# 3. Dependencies fresh
flutter pub get
dart run build_runner build --delete-conflicting-outputs

# 4. Tests pass
flutter analyze                            # expect: 0 errors, 0 warnings (info-level is fine)
flutter test                               # expect: 79 passing (number may shift)

# 5. Dev box reachable
ssh dev 'uptime'                           # expect: response, not hang

# 6. Physical device paired
xcrun devicectl list devices | grep -i iphone   # expect: Craig's iPhone available

# 7. Last-known-good release build still viable
xattr -cr .
flutter build ios --release                # expect: ✓ Built build/ios/iphoneos/Runner.app
```

If any of these fails, fix that before feature work. Do NOT assume prior state.

---

## 19. Do not change without caution

- `lib/shared/storage/secure_storage.dart` SecretKeys class — adding is safe; **renaming breaks existing users' Keychain entries**
- `lib/features/command_templates/data/builtin_templates.dart` — **never change existing IDs**; add new ones only
- `lib/features/ssh/domain/ssh_client.dart` — the whole app routes through this interface; a breaking change touches dozens of files
- `ios/Runner/Info.plist` — bundle ID, required background modes, and any URL schemes must survive merges
- `pubspec.yaml` version bumps — especially Flutter / Dart / Riverpod / dartssh2 / Drift — do in a separate commit, run full test suite
- `ios/Runner.xcodeproj/project.pbxproj` DEVELOPMENT_TEAM — if missing, re-add `RT2UR47KNW`; if replaced with a different team, signing breaks

---

## 20. Immediate next actions

If a new agent takes over today, the highest-leverage sequence is:

1. **Verify toolchain + green tests** (§18) — 5 min
2. **Flip Stripe live test** — run a real £15.99 purchase on `opspocket.com/cloud`, refund after, confirm welcome email arrives with the pair deep-link — 15 min (user action)
3. **Build app pairing handler** (§7.1) — 1 day
4. **Ship to TestFlight** — 2 hours (App Store Connect setup + build upload)

Everything else is optional polish.

---

## 21. Credentials + secrets — reference only

**No secret values are stored in this document.** Locations and key names only:

| Secret | Where it lives | Notes |
|---|---|---|
| Hetzner API token | dev box `/etc/opspocket/hetzner-token` (mode 0600) — or fallback `/root/.hetzner-token` | used by orchestrator + `test-installer.sh` |
| Cloudflare API token (Caddy DNS-01) | dev box `/etc/caddy/cloudflare.env` | `systemctl restart caddy` after changing — reload does NOT pick it up |
| Cloudflare API token (orchestrator DNS writes) | dev box `/etc/opspocket/cloudflare-token` or `/root/.cloudflare-token` | |
| Stripe live secret key | dev box `/etc/opspocket/stripe-api-key` (mode 0600) | `sk_live_…` |
| Stripe live webhook signing secret | dev box `/etc/opspocket/stripe-webhook-secret` (mode 0600) | `whsec_…` |
| Resend sending API key | dev box `/etc/opspocket/resend-api-key` + `/etc/opspocket/email-resend-key` (same content) | `re_…`, sending-only permission |
| Admin panel basic-auth | bcrypt hash in `infra/caddy-sites/opspocket.caddy` under `@admin_api` + `@admin_page`; plaintext in dev box `/etc/opspocket/admin-creds.txt` | rotate with `caddy hash-password` |
| Apple Developer account password | Not stored here; findgriff@gmail.com; signing is automatic |
| App signing identity | Xcode manages locally via Team ID `RT2UR47KNW` |
| Mac's SSH key for `ssh dev` | `~/.ssh/id_ed25519` on Craig's Mac | Public key is on dev box `~root/.ssh/authorized_keys` |
| Tenant-per-VPS clawmine passwords | `/root/CREDENTIALS.json` on each tenant box | authoritative copy per-tenant |
| Tenant registry | dev box `/root/tenants.json` + committed `infra/tenants.json` | written by `provision-tenant.sh` |

**Test/scratch fixtures that may have been left on the dev box this session (not real production secrets):**

- `apptest` SSH user (UID 1001, in `sudo` group) — password set during this session, rotate or remove if stale. Check `id apptest` on dev box. Created specifically so the iPhone app could SSH in for manual testing.
- `clawd` alias user (UID shared with `openclaw`, i.e. 1000) in `/etc/passwd` + `/etc/shadow` — added so `mc_repository.dart` style `su - clawd -c '...'` commands resolve. Locked hash or simple test password; treat as disposable.
- pam_wheel trust setting in `/etc/pam.d/su` — allows members of `sudo` group to `su` without target password. Non-default; may want to revert.

---

## 22. Outstanding — exact list to go live (business + app)

### Business (Cloud platform)

- ❓ Run first real £15.99 Starter purchase (owner action, 10 min)
- ❓ Confirm welcome email arrives with pair deep-link button (will be visible after action above)
- ❓ Confirm `/account` shows the invoice after first purchase
- ❓ Destroy the old DigitalOcean droplet `188.166.150.21` (still reachable as of 2026-04-23 per audit logs; should be Destroyed not Powered Off)

### App (iPhone)

- 🎯 Pairing deep-link handler (§7.1, §5, §7)
- 🎯 SFTP/Files restored (§4) — optional
- 🎯 TestFlight distribution
- 🎯 App Store readiness (privacy manifest, screenshots, metadata)

Once the pairing handler ships + TestFlight is live, a customer can go from **Stripe purchase → phone app fully configured** in under 15 minutes, zero manual credential typing. That's the ship-worthy milestone.

---

*End of HANDOVER. For agent-specific operating instructions, read `CLAUDE.md` next.*
