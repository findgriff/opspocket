# OpsPocket security notes & threat model

Last updated: MVP release.

## Assets we protect

| Asset | Where it lives |
|---|---|
| SSH private key bodies | `flutter_secure_storage` — OS keychain (Android Keystore / iOS Keychain). Never in Drift/SQLite. |
| SSH key passphrases | `flutter_secure_storage`, separate key per server. |
| Provider API tokens (DigitalOcean) | `flutter_secure_storage`. |
| Host key fingerprints | Drift/SQLite. Treated as non-secret, integrity-sensitive. |
| Audit trail (commands + output summaries) | Drift/SQLite, on-device only. Output is sanitised before writing. |
| Server metadata (host, port, user, nickname, tags) | Drift/SQLite. Non-secret. |

## Trust boundary

```
[User]  -->  [Flutter UI]
            |
            v
    [Riverpod notifiers / CommandRunner]
            |
            +--> [SshClient (dartssh2)]  --TLS/SSH-->  [User's VPS]
            |
            +--> [DigitalOceanApi (dio)] --HTTPS-->   [api.digitalocean.com]
            |
            +--> [Drift (SQLite)]        local disk
            +--> [flutter_secure_storage] OS keychain
            +--> [local_auth]            OS biometrics
```

Only the UI and the SSH/HTTPS client are exposed to the network. All persistence is local.

## Threats considered

### T1 — Device lost / stolen

**Mitigation:**
- Biometric / device-credential lock (opt-in but strongly recommended in onboarding copy).
- Private keys and tokens in OS keychain with `first_unlock_this_device` (iOS) and `encryptedSharedPreferences: true` (Android).
- Configurable app-lock timeout.

**Residual risk:** If the device is unlocked and the attacker is fast, they can run recovery actions. Destructive-command gates (typed-word confirmation, optional biometric re-auth) add friction. For sensitive deployments, enable biometric lock and keep app-lock timeout short.

### T2 — Malicious MITM / host-key swap

**Mitigation:** Trust-on-first-use: on first connect we capture the host-key fingerprint; on subsequent connects we hard-fail if it changes. User must explicitly clear the stored fingerprint to re-trust.

**Residual risk:** First connect is vulnerable unless the user verifies the fingerprint out-of-band. UI shows the fingerprint in the connection banner to support manual verification. We don't currently preload expected fingerprints — candidate for a future improvement (signed fingerprint bundle).

### T3 — Secret leakage via audit / logs

**Mitigation:** `Sanitizer` redacts known token shapes (DO `dop_v1_…`, AWS `AKIA…`, GitHub `gh[pousr]_…`, bearer headers, `api_key=…`, OpenSSH PRIVATE KEY blocks) before any string is written to the audit trail or displayed in error toasts. Output is truncated to 500 chars in audit summaries.

**Residual risk:** The sanitizer is pattern-based, not exhaustive. A novel token format will not be stripped. The terminal screen intentionally shows raw output to the user (but not to the audit trail). Users with extreme secrecy needs should assume the terminal output is visible to whoever holds the device.

### T4 — Accidental destructive command

**Mitigation:**
- `DangerDetector` flags destructive patterns (rm -rf, dd, mkfs, shutdown, reboot, docker system prune, kubectl delete, drop database, etc.).
- Templates can be marked `dangerous: true` explicitly.
- Flagged commands require typed-word confirmation (`CONFIRM`).
- Optional biometric re-auth on dangerous actions.
- Quick Actions visually flag restart/reboot tiles with a red border.

**Residual risk:** Users can always type raw commands that bypass template danger flags. Pattern-based detection is advisory; a determined user can wrap a destructive command in a script. We accept this — the app is for operators, not a general-purpose sandbox.

### T5 — Compromised DigitalOcean token

**Mitigation:**
- Token stored only in OS keychain.
- Never logged.
- DO API calls use Dio with the Authorization header set only at client construction; no interceptor logging.
- Provider-reboot / power-cycle require typed-confirm + biometric.
- User can revoke the token on the DigitalOcean side at any time; the credential can also be deleted from Settings.

### T6 — SQLite file extraction

**Mitigation:** SQLite contains no secrets (keys and tokens are in the keychain). Worst case is metadata leakage: server hostnames, usernames, nicknames, audit log summaries. For iOS this is already in Data Protection Class C by default; Android Data-at-Rest is tied to device encryption.

**Residual risk:** Audit output snippets may contain operationally sensitive info even after sanitisation. Settings includes a "Clear all audit logs" action.

### T7 — Supply-chain / package compromise

We use:
- `dartssh2` — pure-Dart SSH, active project, widely used.
- `flutter_secure_storage` — de-facto standard.
- `local_auth` — official Flutter team plugin.
- `drift` / `sqlite3_flutter_libs` — widely used, well-audited.
- `dio` — popular HTTP client.
- `go_router` — official Flutter team package.

Package pinning is via `pubspec.yaml` minimums; `pubspec.lock` should be committed for reproducible builds. On each release, audit `pubspec.lock` diffs.

### T8 — Biometric bypass / spoofing

**Mitigation:** We defer to `local_auth` / platform biometric APIs. Biometric failure falls back to device credential (PIN/pattern). If both fail, the action is denied.

### T9 — Clipboard leakage

We copy output to the clipboard on user request. On iOS, the universal pasteboard may sync across devices if iCloud is enabled — this is a platform setting outside our control. Users can disable universal clipboard in iOS settings.

### T10 — Reverse engineering / tampered build

**Not mitigated in MVP.** We don't ship with root detection or anti-tampering. An attacker with a modified build can bypass all app-level gates. For an MVP targeting the founder's own servers this is acceptable. A Pro-tier enterprise build could add Play Integrity / App Attest hooks.

## Things we deliberately don't do

- **We don't roll our own crypto.** All cryptography is delegated to `dartssh2`, platform keychains, and TLS.
- **We don't store passwords.** Password SSH auth is per-connection only.
- **We don't sync to a backend.** All data is local.
- **We don't send telemetry.** No analytics SDKs included.
- **We don't attempt to work around broken host keys.** A mismatched fingerprint is a hard fail, not a warning.

## Reporting vulnerabilities

Please open a private security issue on the repo. For MVP we don't have a formal bounty programme; responsible-disclosure credit in release notes is standard.
