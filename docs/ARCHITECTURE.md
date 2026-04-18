# Architecture

This document expands on the short README overview.

## Layer map

```
+----------------------------------------------------------+
|                    PRESENTATION                          |
|   Screens, widgets, Riverpod notifiers (StateNotifier)   |
+----------------------------------------------------------+
                          |
                          v
+----------------------------------------------------------+
|                       DOMAIN                             |
|   Abstract repositories, SshClient interface, entities   |
+----------------------------------------------------------+
                          |
                          v
+----------------------------------------------------------+
|                        DATA                              |
|   Drift DAOs, dartssh2 impl, dio clients, secure store   |
+----------------------------------------------------------+
                          |
                          v
+----------------------------------------------------------+
|                  PLATFORM / NETWORK                      |
|  SQLite, OS Keychain, local_auth, SSH, DO API            |
+----------------------------------------------------------+
```

Feature modules (`lib/features/*`) each follow this same triangle internally: `domain/`, `data/`, `presentation/`.

`lib/shared/` is cross-cutting: domain entities that multiple features use (`models/`), the central Drift DB (`database/`), the secure-storage wrapper (`storage/`), and app-wide Riverpod providers (`providers/`).

## Startup sequence

1. `main.dart` wraps the app in `ProviderScope`.
2. `OpsPocketApp` reads the router provider (`appRouterProvider`) and constructs `MaterialApp.router`.
3. Initial route `/` loads `SplashUnlockScreen`, which:
   - Seeds built-in command templates (`seedBuiltinsIfEmpty`).
   - Seeds default quick actions (`seedDefaultsIfEmpty`).
   - Reads `biometric_lock` setting; if enabled, prompts `local_auth`.
   - On success, `context.go('/servers')`.
4. Server list screen watches `serverProfilesStreamProvider` (a Drift `watchAll` stream).

## SSH command path

```
Terminal screen (or Quick Action, or Logs)
       |
       v
CommandRunner.run(ctx, serverId, command)
       |
       | 1) check DangerDetector + template.dangerous
       |    -> DangerousConfirmDialog + optional biometric
       v
sshConnectionProvider(serverId) — connect if needed
       |
       v
SshClient.exec(command)  [dartssh2 behind SshClient interface]
       |
       v
CommandExecutionResult  ->  Audit log  ->  Display
```

The `CommandRunner` is the single place where danger-gating, SSH connection-readiness, execution, and auditing are orchestrated. Adding a new entry point (e.g. a voice command) only needs to call `CommandRunner.run`.

## Host key trust

`SshConnectionNotifier._resolveHostKey` implements the TOFU policy:

| State | Action |
|---|---|
| No stored fingerprint (first contact) | Accept, persist `HostFingerprintRecord`. |
| Stored matches presented | Accept, bump `lastSeenAt`. |
| Stored ≠ presented | Throw `HostFingerprintMismatchError`, save `pendingChallenge` so UI can surface an explicit re-trust flow. |

## Provider fallback

`ProviderApi` (abstract) sits in `lib/features/providers/domain/`. `DigitalOceanApi` is the only current impl. `ProviderFallbackDialog` picks the credential from `ProviderCredentialRepository`, reads the token from secure storage *only at send-time*, and performs status / reboot / power-cycle through the API.

Adding AWS: implement `ProviderApi` with AWS SDK (either by hand via dio+SigV4 or via a bundled client), register in the fallback dialog.

## Test strategy

- Pure-logic utilities (placeholder substitution, danger detection, sanitizer) have unit tests.
- Repositories have round-trip tests against `AppDatabase.forTesting(NativeDatabase.memory())` — no real SQLite file needed.
- Secure storage uses an in-memory fake (`InMemorySecureStorage`) that satisfies the `SecureStorage` contract.
- SSH and provider clients are covered by interfaces; tests that need them use mocks (via `mocktail`). MVP doesn't ship SSH integration tests — those require a live sshd and aren't appropriate for unit suites.

## Adding a feature — the short checklist

1. Decide if it's a new `features/<name>` module or an extension of an existing one.
2. Define domain interfaces first (`<feature>/domain/*`).
3. Implement in `<feature>/data/*`. Any new Drift tables go into `lib/shared/database/tables.dart`; re-run codegen.
4. Build presentation (`<feature>/presentation/*`) on top of Riverpod providers.
5. Add tests in `test/`.
6. Wire routes in `lib/app/router/app_router.dart` if the feature has a screen.
