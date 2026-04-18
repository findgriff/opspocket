# OpsPocket

**Emergency VPS recovery, bots, and AI services — from your phone.**

OpsPocket is a Flutter-based mobile incident recovery app. It is *not* a general-purpose SSH client. It is a focused tool for the moment when your bot dies, your AI worker crashes, or your VPS goes silent and you need to restart a service, tail logs, or reboot the box in under a minute — without opening a laptop.

## Status

- **Platform:** Android first, iOS-ready architecture
- **State:** MVP. All MVP feature areas in the spec are implemented and pass `flutter analyze` (0 errors / 0 warnings) and `flutter test` (40/40 green).
- **Flutter:** tested against Flutter 3.41.6 / Dart 3.11.

## Running it

1. Install the Flutter SDK: https://docs.flutter.dev/get-started/install
2. From the repo root:

   ```bash
   flutter pub get
   flutter pub run build_runner build --delete-conflicting-outputs
   flutter run -d android
   ```

3. On first launch the app seeds built-in command templates and quick actions. Add a server in the Servers screen to start.

### Running the test suite

```bash
flutter test
```

### Using the included Docker workflow (no local Flutter install needed)

```bash
docker run --rm \
  -v "$(pwd)":/app -v opspocket_pub_cache:/root/.pub-cache \
  -w /app -u root ghcr.io/cirruslabs/flutter:stable bash -c '
    flutter pub get && \
    dart run build_runner build --delete-conflicting-outputs && \
    flutter analyze && flutter test
  '
```

## What's in the MVP

- **Server profiles** — add, edit, delete, favourite, search. Private keys stored in OS keychain (Keystore on Android, Keychain on iOS), never the SQLite DB.
- **SSH connection layer** — `dartssh2`-backed. Host-key trust-on-first-use with hard-fail on mismatch. All SSH details live behind an `SshClient` interface (`lib/features/ssh/domain/ssh_client.dart`) so we can swap to a native bridge later.
- **Terminal screen** — practical command console. Exec-per-command (no PTY emulation) — better for mobile networks, matches the recovery use case.
- **Slash command palette** — fuzzy search over seeded + user templates, `{{placeholder}}` prompts, preview before execution, explicit danger flag for destructive commands.
- **Quick Actions** — big-button grid for the 7 most common recovery flows (status, logs, restart service, restart bot, Docker restart, PM2 restart, reboot).
- **Logs viewer** — journald / docker / pm2 / file presets, line-count control, preserves monospace, cap on display size (100 KB) so tail of a 10-MB log doesn't OOM the UI.
- **DigitalOcean fallback** — reboot or power-cycle a droplet via API when SSH can't reach it. Token in secure storage, credential label in DB.
- **Audit trail** — every SSH connect, command run, provider action, settings change is logged locally. Filter by server / by success/failure. Output snippets are sanitised (see `Sanitizer`) before logging.
- **Biometric & app lock** — opt-in biometric unlock, biometric confirm for destructive actions, typed-word confirmation for dangerous commands.
- **Settings** — app-lock toggle & timeout, default log line count, terminal font size, DO token management, clear audit.

## Architecture

Clean Architecture with Riverpod + go_router.

```
lib/
  app/
    app.dart              - MaterialApp.router shell
    router/               - go_router config + Routes constants
    theme/                - dark-first theme, monospace helpers
    core/                 - errors, utils (placeholder, danger, sanitizer), widgets, constants
  features/
    auth_security/        - biometric gate, splash/unlock
    server_profiles/      - CRUD
    ssh/                  - interface + dartssh2 impl + connection notifier + command runner
    terminal/             - command console
    command_templates/    - registry, builtin seeds, slash palette, placeholder prompt
    quick_actions/        - big-button grid
    logs/                 - log presets screen
    providers/            - DigitalOcean fallback (modular provider interface)
    audit/                - local audit trail
    settings/             - settings screen + repository
  shared/
    models/               - domain entities
    database/             - Drift tables, mappers, DB singleton
    providers/            - shared Riverpod providers
    storage/              - SecureStorage abstraction
test/
  placeholder_utils_test.dart
  danger_detector_test.dart
  sanitizer_test.dart
  builtin_templates_test.dart
  secure_storage_fake_test.dart
  repositories_test.dart
```

Each feature module follows `data / domain / presentation` where meaningful. Domain defines interfaces; data implements them (Drift, dartssh2, dio); presentation consumes them through Riverpod.

### Key design decisions

- **Exec-per-command, not PTY.** MVP runs each submitted command via `SSHClient.execute` and captures stdout/stderr as a bounded buffer. We do not attempt full terminal emulation. Rationale: mobile networks drop; PTY sessions die ugly; the recovery use case is one command, one result, move on.
- **Trust-on-first-use (TOFU) host keys.** First connection records the host-key fingerprint. Subsequent connects compare and hard-fail on mismatch. Users can explicitly clear a fingerprint to re-trust.
- **Secrets never in Drift.** Private key bodies, SSH passphrases, and provider tokens live only in `flutter_secure_storage`. The SQLite DB holds only labels and secure-storage keys.
- **Danger is a first-class concept.** `DangerDetector` flags destructive commands by pattern *plus* template-declared `dangerous: true`. Flagged commands require typed-word confirmation; optionally biometric re-auth.
- **Provider fallback is modular.** `ProviderApi` abstract class; `DigitalOceanApi` implements it. Adding AWS / Hetzner / Linode later is a new class + registration.
- **Riverpod without code generation.** Keeps the moving parts down; only Drift + freezed require `build_runner`.

## Security

See `docs/SECURITY.md` for the full threat model.

Highlights:

- **Data at rest:** secrets in OS keychain; SQLite DB contains only non-secret metadata. On Android we use `encryptedSharedPreferences: true`; on iOS `first_unlock_this_device`.
- **Secret redaction in audit logs:** the `Sanitizer` strips DO tokens, bearer headers, api_key assignments, OpenSSH private key blocks, AWS access keys, and GitHub tokens before writing to the audit trail.
- **Destructive command gating:** typed-word confirmation (`DangerousConfirmDialog`), optional biometric re-auth, template `dangerous` flag, pattern-based detection via `DangerDetector`.
- **Host-key pinning:** first-contact capture + mismatch hard-fail.
- **Biometric / app lock:** opt-in; falls back gracefully on devices without it.
- **Provider API isolation:** token header injected only at client construction, never logged.

## MVP limitations (known, intentional)

- **No SFTP / file browser.** Out of scope for the recovery use case.
- **Password auth** is supported per connection but passwords are never persisted.
- **No full terminal emulation.** No ANSI colours, no interactive TUI programs (htop, vim). Use `command; exit` style commands.
- **Provider fallback = DigitalOcean only.** Interface supports adding more; MVP ships one.
- **No push notifications / uptime dashboards.** Out of scope.
- **No cross-device sync / team accounts.** Local-only by design.

## Roadmap ideas (post-MVP)

- Native SSH bridge (MethodChannel) if `dartssh2` hits edge cases on specific Android versions
- AWS EC2 and Hetzner Cloud provider implementations
- Persistent shell session mode for long-running investigations
- Shared team templates via a minimal backend
- Push alerts when a saved health command returns non-zero

## Commercial notes

Intended model: Free tier = 1 saved server, Pro = £3/month for unlimited + quick actions + provider fallback. The app keeps a `freeTierServerLimit` constant and is structured so enforcing it is an `if`-check at add-server time. Billing is intentionally not wired up in the MVP.

## Contributing

- Run `flutter pub run build_runner build --delete-conflicting-outputs` after editing Drift tables or freezed models.
- `flutter analyze` should stay at zero errors / warnings.
- Add tests for any pure-logic change (`test/*_test.dart`).

## Licence

MIT — see `LICENSE`.
