# CLAUDE.md — OpsPocket Project Instructions

**IMPORTANT: Always read `HANDOVER.md` at the start of every session before doing anything else.**
`HANDOVER.md` is the authoritative record of all changes made to this project. It documents every bug fix, feature addition, architecture decision, and planned work. Do not assume you know the current state of the project — check `HANDOVER.md` first.

---

## Project Summary

OpsPocket is a Flutter/iOS mobile SSH console for managing VPS servers, bots, and AI services (specifically OpenClaw/Clawbot). It is production-quality, iPhone-first, and security-conscious.

**Bundle ID:** co.opspocket.opspocket  
**Flutter:** 3.41.7 / Dart 3.11.5  
**Primary working directory:** the root of this repo

---

## Architecture

- **State management:** Riverpod (`StateNotifierProvider.family` for per-server state)
- **Routing:** GoRouter (`lib/app/router/app_router.dart`)
- **SSH:** dartssh2, always accessed through the `SshClient` interface (`lib/features/ssh/domain/ssh_client.dart`) — never import dartssh2 directly in feature code
- **Database:** Drift (SQLite) — always run `dart run build_runner build --delete-conflicting-outputs` after schema changes
- **Secrets:** `flutter_secure_storage` (iOS Keychain) — see `lib/shared/storage/secure_storage.dart` for key naming conventions
- **Theme:** `lib/app/theme/app_theme.dart` — OpsClaw palette (red/black/cyan). Never hardcode colours; always use `AppTheme.*` or the local palette constants in terminal_screen.dart
- **Font:** JetBrains Mono for all monospace/terminal text via `AppTheme.mono()`

---

## Coding Rules

1. **Read before editing.** Never propose changes to a file you haven't read.
2. **Follow existing patterns.** Riverpod providers, error types (`AppError` hierarchy), and repository pattern are all established — extend them, don't replace them.
3. **No raw dartssh2 types in feature code.** All SSH access goes through `SshClient` or `CommandRunner`.
4. **Secrets never in memory longer than needed.** Passwords and keys are read from Keychain at connect time and not stored in state.
5. **Builtin command templates have stable IDs.** Never change an existing builtin ID — it will create duplicates. Add new ones with new IDs.
6. **After any model/database change:** run `dart run build_runner build --delete-conflicting-outputs`.
7. **App icon changes:** uninstall from simulator first (`xcrun simctl uninstall booted co.opspocket.opspocket`) to clear cache.

---

## Files You Will Commonly Touch

| File | Purpose |
|---|---|
| `lib/app/theme/app_theme.dart` | Colours, typography, component themes |
| `lib/app/router/app_router.dart` | All routes |
| `lib/features/terminal/presentation/terminal_screen.dart` | Main terminal UI |
| `lib/features/server_profiles/presentation/server_detail_screen.dart` | Per-server detail + action tiles |
| `lib/features/command_templates/data/builtin_templates.dart` | Built-in slash commands |
| `lib/features/ssh/domain/ssh_client.dart` | SSH interface — add methods here first |
| `lib/features/ssh/data/ssh_client_impl.dart` | dartssh2 implementation |
| `lib/shared/storage/secure_storage.dart` | Keychain key names |
| `pubspec.yaml` | Dependencies and asset registration |

---

## Planned Work (check HANDOVER.md for latest status)

- **ClawGate** — SSH tunnel to OpenClaw browser UI. Spec at `docs/superpowers/specs/2026-04-17-clawgate-design.md`. Not yet implemented.

---

## Running & Building

```bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter run -d "iPhone 16"
```
