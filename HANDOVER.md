# OpsPocket — Project Handover

**Last updated:** 2026-04-22
**Bundle ID (app):** co.opspocket.opspocket
**Flutter:** 3.41.7 / Dart 3.11.5

---

## Project Overview

OpsPocket is now two products under one brand:

- **OpsPocket (App)** — Flutter iOS SSH/VPS console for managing VPS servers, bots and AI services (OpenClaw/Clawbot). Shipping.
- **OpsPocket Cloud** — managed OpenClaw hosting on Hetzner. Waitlist-stage; marketing site live, auto-provisioning orchestrated by `infra/provision-tenant.sh`. Not yet billable.

Both share the same repository. The iOS app is unchanged since 2026-04-17; all work this session has been on Cloud infra, the marketing site migration, and a 6-site consolidation off DigitalOcean.

---

## Architecture

### iOS app stack (unchanged)

- **State management:** Riverpod (`StateNotifierProvider.family` per server)
- **Routing:** GoRouter (`lib/app/router/app_router.dart`)
- **SSH:** `dartssh2`, accessed only via the `SshClient` interface (`lib/features/ssh/domain/ssh_client.dart`)
- **Database:** Drift (SQLite) — regenerate with `dart run build_runner build --delete-conflicting-outputs`
- **Secrets:** `flutter_secure_storage` (iOS Keychain) — see `lib/shared/storage/secure_storage.dart`
- **Theme:** `lib/app/theme/app_theme.dart` — OpsClaw palette (red/black/cyan), JetBrains Mono throughout
- **Feature modules** (`lib/features/`): `server_profiles`, `ssh`, `terminal`, `command_templates`, `splash`, `tunnel`, `mission_control`, `quick_actions`, `server_health`, `logs`, `files`, `audit`, `auth_security`, `settings`

### Cloud stack (new)

- **Host:** single Hetzner CX43 in Nuremberg, `opspocket-dev` at `178.104.242.211`. Currently doubles as developer workshop, production host for the marketing site and migrated legacy sites, and test harness for tenant provisioning.
- **Provisioning:** `infra/install-openclaw.sh` — idempotent installer that brings up OpenClaw + Docker + Caddy + Cloudflare DNS-01 TLS on a bare Ubuntu 24.04 Hetzner VPS. Supports `MODEL_PROVIDER=ollama` for free-tier builds.
- **Orchestration:** `infra/provision-tenant.sh` — manual-MVP onboarding. Creates a Hetzner VM, points a Cloudflare A record at it, runs the installer over SSH, writes tenant record to `infra/tenants.json`.
- **Interactive first-run:** `infra/first-deploy.sh` — wizard around `provision-tenant.sh` for the very first Hetzner deploy.
- **TLS:** Caddy with the Cloudflare DNS-01 plugin. Single `CLOUDFLARE_API_TOKEN` held in `/etc/caddy/cloudflare.env` on the dev box.
- **Multi-site Caddy:** per-site configs in `/etc/caddy/Caddyfile.d/*.caddy`, source-of-truth at `infra/caddy-sites/`. Main `Caddyfile` just does `import Caddyfile.d/*.caddy`.
- **Waitlist backend:** `infra/waitlist-server.py` (48-line Python HTTP service on 127.0.0.1:8091), systemd unit `infra/opspocket-waitlist.service`. Appends to `/var/lib/opspocket/waitlist.txt`.
- **Test harness:** `infra/test-installer.sh` — smoke-test that drives `install-openclaw.sh` end-to-end on a disposable `*.dev.opspocket.com` subdomain.

---

## Sites currently served from the dev box

All TLS via Let's Encrypt with Cloudflare DNS-01. Per-site Caddy configs at `infra/caddy-sites/`.

| File | Hostnames | Backend | Purpose |
|---|---|---|---|
| `opspocket.caddy` | opspocket.com, www | static `/var/www/opspocket.com` + `/api/waitlist` → 127.0.0.1:8091 | Public marketing + Cloud waitlist |
| `dev.caddy` | hello.dev.opspocket.com, *.dev.opspocket.com | respond | Dev-box health, test-tenant catch-all |
| `dafc.caddy` | darleyabbeyfc.com, www | static `/var/www/darleyabbeyfc.com` | Darley Abbey FC |
| `dafc-forms.caddy` | forms.darleyabbeyfc.com | 127.0.0.1:5102 | DAFC forms handler |
| `forms-api.caddy` | forms.aressentinel.com | 127.0.0.1:5103 | Forms API + MariaDB |
| `glowpower.caddy` | glowpower.co.uk, www | 127.0.0.1:5100 | Glow Power site |
| `magichairstyler.caddy` | magichairstyler.com, www | static `/var/www/magichairstyler.com` | Magic Hair Styler |
| `vantabiolabs.caddy` | vantabiolabs.xyz, www | 127.0.0.1:5101 | Vanta Bio Labs |

Reverse-proxy port map and full details in `infra/caddy-sites/README.md`.

---

## What's live for Cloud

### Marketing site

- `https://opspocket.com` — hand-rolled `site-v2/index.html` (1700+ lines, preserved from the DO original). Added:
  - Cloud link in the main nav
  - "Managed Cloud" band between hero and ticker
  - Extended schema.org `Offer` array covering Cloud tiers
- `https://opspocket.com/cloud` — new `site-v2/cloud.html`, same visual language as the homepage: pricing grid with monthly/annual toggle, how-it-works, feature grid, competitor comparison, FAQ, waitlist modal
- `https://opspocket.com/blog/*` — 4 original posts preserved verbatim (mission-control, getting-started-ssh, marketing-pipeline, the-bridge)
- `POST /api/waitlist` — writes to `/var/lib/opspocket/waitlist.txt` on the dev box

### Pricing tiers (GBP; not yet billable)

| Tier | Monthly | Annual | App bundled? | Hetzner type |
|---|---|---|---|---|
| Starter | £15.99/mo | £176.59/yr (~£14.72/mo) | ✓ free with annual only | CPX22 (2 vCPU / 4 GB / 80 GB) |
| Pro | £22.99/mo | £234.50/yr (15% off) | ✓ always | CPX32 (4 vCPU / 8 GB / 80 GB) |
| Agency | £34.99/mo | £356.90/yr (15% off) | ✓ always | CPX42 (8 vCPU / 16 GB / 160 GB) |

Full rationale and design: `docs/superpowers/specs/2026-04-22-opspocket-site-migration-design.md`.

---

## Testing infrastructure

### `infra/test-installer.sh`

Smoke-tests `install-openclaw.sh` end-to-end:

1. Spawns a throwaway Hetzner VM
2. Allocates a test subdomain under `*.dev.opspocket.com`
3. SSHes in and runs the installer
4. Verifies OpenClaw gateway responds on the tenant URL
5. Destroys the VM

Use before merging any installer change. It is the only way to catch regressions in the installer short of real tenant provisioning.

```bash
./infra/test-installer.sh
```

---

## All changes since 2026-04-17

Chronological, newest last:

1. **`3e374f7` Update all logos to OpsPocket official branding** — replaced placeholder logos app-wide.
2. **`be51dfe` Replace OpenClaw UI tunnel logo with new OpsPocket branding** — updated the tunnel screen asset.
3. **`7af0c33` feat(site+infra): landing site + managed-VPS installer scaffold** — first cut of the Next.js landing site and the `install-openclaw.sh` scaffold.
4. **`7547c6f` feat(infra): nginx config + one-shot deploy script for the landing site** — initial deploy path (since superseded by Caddy).
5. **`76be5ee` feat(infra): vps-build-site.sh — pull + build on the VPS itself** — pull/build helper on target VPS.
6. **`ad9f9b0` chore(infra): build site from main (now that landing-site is merged)** — aligned build branch.
7. **`9b0af49` fix(infra): handle branch switch when VPS checkout was previously on landing-site** — resilience for re-deploys.
8. **`dead9d5` chore(infra): capture Vultr Marketplace OpenClaw install blueprint** — reference material under `infra/vultr-recce/`.
9. **`3b3468d` chore(infra): capture OpenClaw-generated installer script + review** — baseline for rewriting the installer.
10. **`78a0414` fix(infra): install-openclaw.sh — all 8 bugs from REVIEW.md fixed** — hardening pass on the installer.
11. **`06f5187` feat(infra): provision-tenant.sh — manual onboarding MVP** — single-command tenant provisioning.
12. **`42bbc15` feat(infra): first-deploy.sh — interactive wizard for first Hetzner deploy** — guided first-run.
13. **`1846645` feat(infra): install-openclaw.sh — add MODEL_PROVIDER=ollama for free-tier deploys** — lets Starter tier run local Ollama instead of paid OpenAI.
14. **`73c4cc0` feat(infra): dev box + installer fixes from Hetzner dry-run** — fixes discovered during the first live Hetzner run.
15. **`5d1378a` docs(spec): opspocket.com migration + Cloud pricing design** — design doc for this session's work.
16. **`403b6b7` feat(site): migrate opspocket.com to dev box + add Cloud pricing page** — swung the marketing site onto the dev box, added `/cloud`.
17. **`925aabe` feat(infra): migrate 6 sites off DigitalOcean Dokku → Hetzner dev box** — six-site parallel cutover. Details in `infra/MIGRATION-LOG.md`.

---

## Known issues

- **`www.magichairstyler.com` → root redirect** — `infra/caddy-sites/magichairstyler.caddy` has the standard `redir https://magichairstyler.com{uri} permanent` block, identical to the pattern used for `opspocket.com` and `glowpower.co.uk`. Users have reported the redirect not firing on some paths. Suspect a Cloudflare edge cache of an earlier failing response; purge `www.magichairstyler.com/*` at the CF edge and re-test. If that doesn't fix it, compare headers against `www.glowpower.co.uk` which uses the same pattern successfully.

---

## Outstanding work

### Cloud (to go from waitlist → sellable)

- **Stripe integration** — Checkout sessions for all three tiers, monthly + annual.
- **Customer welcome email template** — transactional email on signup + on provisioning-complete.
- **Signup orchestrator** — auto-run `provision-tenant.sh` on Stripe `checkout.session.completed` webhook; wire in failure/retry logic.
- **Customer account dashboard** — `opspocket.com/account`: login, tier, billing, VPS status, basic ops (reboot, re-provision, download creds).
- **SaaS admin panel** — founder-only view of tenants, revenue, live boxes, logs.
- **Destroy DigitalOcean droplet** — `188.166.150.21` is still alive as emergency rollback for the 6-site migration. Kill once the dev box has run cleanly for a few more days.

### App

- **Mission Control** — iPhone polish pass + MCP wiring for OpenClaw 2026.4.5. Status unchanged from 2026-04-17.
- **ClawGate** — SSH-tunnel UI to the OpenClaw browser UI. Spec at `docs/superpowers/specs/2026-04-17-clawgate-design.md`; not implemented. Status unchanged from 2026-04-17.

---

## Credentials & secrets on the dev box

Everything secret lives on `opspocket-dev` and nowhere in the repo. Locations:

| Secret | Path on dev box | Notes |
|---|---|---|
| Hetzner API token | `/root/.hetzner-token` (mode 0600) | Used by `provision-tenant.sh` and `test-installer.sh` |
| Cloudflare API token (Caddy DNS-01) | `/etc/caddy/cloudflare.env` | `systemctl restart caddy` after changing — reload does NOT re-read `EnvironmentFile` |
| Cloudflare API token (provisioner, DNS writes) | `/root/.cloudflare-token` (mode 0600) | Used by `provision-tenant.sh` to create tenant A records |
| forms-db MariaDB root password | `/root/forms-db-root.txt` (mode 0600) | Used by forms-api container; rotate with `ALTER USER` inside the container |
| Tenant registry | `/root/tenants.json` + `infra/tenants.json` locally | Written by `provision-tenant.sh` on every successful run |
| Per-tenant credentials | `/root/CREDENTIALS.json` on each tenant VPS | Written by `install-openclaw.sh`; authoritative copy lives on the tenant box |
| Migration artifacts (rollback bundle) | `/root/migration-artifacts/` | ~2 GB; delete after 7 days of stable dev-box operation |

---

## Access

- **SSH:** `ssh dev` from the Mac (key-based; alias in `~/.ssh/config`)
- **Dev box IP:** `178.104.242.211` (Hetzner CX43, Nuremberg)
- **Main URLs:**
  - `https://opspocket.com` — public marketing site
  - `https://opspocket.com/cloud` — Cloud pricing + waitlist
  - `https://hello.dev.opspocket.com` — dev-box health check
  - `https://*.dev.opspocket.com` — test-tenant catch-all

---

## Running the App

```bash
# Install deps + regenerate code
flutter pub get
dart run build_runner build --delete-conflicting-outputs

# Run on simulator
flutter run -d "iPhone 16"

# Clear icon cache after icon changes
xcrun simctl uninstall booted co.opspocket.opspocket
flutter run
```
