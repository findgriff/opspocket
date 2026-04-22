# CLAUDE.md — OpsPocket Project Instructions

**IMPORTANT: Always read `HANDOVER.md` at the start of every session before doing anything else.**
`HANDOVER.md` is the authoritative record of all changes made to this project. It documents every bug fix, feature addition, architecture decision, and planned work. Do not assume you know the current state of the project — check `HANDOVER.md` first.

---

## Project Summary

OpsPocket is two products under one brand, in one repository:

- **OpsPocket (App)** — Flutter/iOS mobile SSH console for managing VPS servers, bots, and AI services (specifically OpenClaw/Clawbot). Production-quality, iPhone-first, security-conscious.
- **OpsPocket Cloud** — managed OpenClaw hosting on Hetzner. Tenant VPS boxes are provisioned by our scripts and fronted by Caddy + Cloudflare. Currently waitlist-stage.

**App bundle ID:** co.opspocket.opspocket
**Flutter:** 3.41.7 / Dart 3.11.5
**Primary working directory:** the root of this repo
**Dev box:** `opspocket-dev` (Hetzner CX43, Nuremberg, `178.104.242.211`) — reachable as `ssh dev`

---

## App Architecture

- **State management:** Riverpod (`StateNotifierProvider.family` for per-server state)
- **Routing:** GoRouter (`lib/app/router/app_router.dart`)
- **SSH:** dartssh2, always accessed through the `SshClient` interface (`lib/features/ssh/domain/ssh_client.dart`) — never import dartssh2 directly in feature code
- **Database:** Drift (SQLite) — always run `dart run build_runner build --delete-conflicting-outputs` after schema changes
- **Secrets:** `flutter_secure_storage` (iOS Keychain) — see `lib/shared/storage/secure_storage.dart` for key naming conventions
- **Theme:** `lib/app/theme/app_theme.dart` — OpsClaw palette (red/black/cyan). Never hardcode colours; always use `AppTheme.*` or the local palette constants in `terminal_screen.dart`
- **Font:** JetBrains Mono for all monospace/terminal text via `AppTheme.mono()`

---

## Cloud Architecture

- **Installer:** `infra/install-openclaw.sh` — idempotent, sole source of truth for what a tenant box looks like. Supports `MODEL_PROVIDER=ollama` for free-tier (local LLM) deploys.
- **Provisioner:** `infra/provision-tenant.sh` — creates Hetzner VM, adds Cloudflare A record, runs the installer over SSH, writes to `infra/tenants.json`.
- **Interactive wizard:** `infra/first-deploy.sh` — walks the operator through a first-time deploy.
- **Test harness:** `infra/test-installer.sh` — spawns a throwaway VM + subdomain, runs the installer end-to-end, destroys.
- **TLS:** Caddy + Cloudflare DNS-01 plugin, single `CLOUDFLARE_API_TOKEN` on the dev box at `/etc/caddy/cloudflare.env`.
- **Multi-site Caddy:** main `/etc/caddy/Caddyfile` does `import Caddyfile.d/*.caddy`; per-site source of truth at `infra/caddy-sites/`.
- **Waitlist backend:** `infra/waitlist-server.py` behind `infra/opspocket-waitlist.service`, proxied by Caddy on `/api/waitlist`.

---

## App Coding Rules

1. **Read before editing.** Never propose changes to a file you haven't read.
2. **Follow existing patterns.** Riverpod providers, error types (`AppError` hierarchy), and repository pattern are all established — extend them, don't replace them.
3. **No raw dartssh2 types in feature code.** All SSH access goes through `SshClient` or `CommandRunner`.
4. **Secrets never in memory longer than needed.** Passwords and keys are read from Keychain at connect time and not stored in state.
5. **Builtin command templates have stable IDs.** Never change an existing builtin ID — it will create duplicates. Add new ones with new IDs.
6. **After any model/database change:** run `dart run build_runner build --delete-conflicting-outputs`.
7. **App icon changes:** uninstall from simulator first (`xcrun simctl uninstall booted co.opspocket.opspocket`) to clear cache.

---

## Cloud Infrastructure Rules

1. **All tenant boxes deploy via `infra/install-openclaw.sh`.** Never SSH into a customer box to fix something by hand — change the installer, re-run, and document. Hand-edits on tenant boxes are guaranteed drift.
2. **Installer changes must pass `infra/test-installer.sh`** before being merged or applied to real tenants. No exceptions.
3. **Customer credentials live in exactly two places:** `/root/CREDENTIALS.json` on the tenant box (authoritative), and the tenant record in `infra/tenants.json` / `/root/tenants.json` on the dev box. Never check credentials into git.
4. **Caddy configs go in `/etc/caddy/Caddyfile.d/*.caddy`**, sourced from `infra/caddy-sites/`. Never edit the main `/etc/caddy/Caddyfile`. Deploy with `scp` + `systemctl reload caddy`.
5. **Changing `CLOUDFLARE_API_TOKEN` requires `systemctl restart caddy`** — `reload` keeps the old in-memory token because systemd only re-reads `EnvironmentFile` on restart. This has burned time before; do not forget.
6. **One Caddy token per box.** Do not scope Cloudflare API tokens per-zone unless there's a clear reason — it means every new domain needs a token rotation.

---

## Files You Will Commonly Touch

### App

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

### Cloud / infra

| File | Purpose |
|---|---|
| `infra/install-openclaw.sh` | Tenant-box installer (idempotent) |
| `infra/provision-tenant.sh` | End-to-end tenant onboarding |
| `infra/first-deploy.sh` | Interactive wizard around provisioning |
| `infra/test-installer.sh` | Installer smoke test |
| `infra/caddy-sites/*.caddy` | Per-site Caddy configs |
| `infra/caddy-sites/README.md` | Port map + add-a-site runbook |
| `infra/waitlist-server.py` | Tiny HTTP service behind `/api/waitlist` |
| `infra/opspocket-waitlist.service` | Systemd unit for the waitlist service |
| `infra/MIGRATION-LOG.md` | DO → Hetzner migration story + learnings |
| `site-v2/index.html` | Public marketing homepage |
| `site-v2/cloud.html` | Cloud pricing + waitlist page |

---

## Planned Work (check HANDOVER.md for latest status)

### Cloud

- **Stripe integration** — Checkout for all three tiers, monthly + annual.
- **Customer welcome email template** — signup + provisioning-complete.
- **Signup orchestrator** — auto-run `provision-tenant.sh` on Stripe webhook.
- **Customer account dashboard** — `opspocket.com/account`.
- **SaaS admin panel** — founder-only tenant + revenue view.
- **Destroy DigitalOcean droplet `188.166.150.21`** once the dev box is stable.

### App

- **Mission Control** — iPhone polish + MCP wiring for OpenClaw 2026.4.5.
- **ClawGate** — SSH tunnel to OpenClaw browser UI. Spec at `docs/superpowers/specs/2026-04-17-clawgate-design.md`. Not yet implemented.

---

## Running & Building

### App

```bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter run -d "iPhone 16"
```

### Dev box ops

```bash
# Log in
ssh dev

# Deploy the marketing site
rsync -a --delete site-v2/ dev:/var/www/opspocket.com/
ssh dev 'systemctl reload caddy'

# Add or change a Caddy site
scp infra/caddy-sites/<app>.caddy dev:/etc/caddy/Caddyfile.d/<app>.caddy
ssh dev 'systemctl reload caddy'

# Rotate the Cloudflare token (restart, NOT reload)
ssh dev 'vim /etc/caddy/cloudflare.env && systemctl restart caddy'

# Read waitlist signups
ssh dev 'cat /var/lib/opspocket/waitlist.txt'

# Smoke-test the installer before merging a change
./infra/test-installer.sh
```

Caddy config pattern: main `/etc/caddy/Caddyfile` is just `import Caddyfile.d/*.caddy` plus the global ACME email; all real config lives in `infra/caddy-sites/*.caddy` and is `scp`'d into place. TLS is always Cloudflare DNS-01 — `tls { dns cloudflare {env.CLOUDFLARE_API_TOKEN} }`.

Snapshot schedule: no automated Hetzner snapshot daemon is in place yet. Take manual snapshots from the Hetzner console before any destructive dev-box change until that's built.
