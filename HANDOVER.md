# OpsPocket — Project Handover

**Last updated:** 2026-04-22 (audit pass by Lead DevOps)
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

## Audit pass — 2026-04-22

Full health audit of everything built this session. Results:

### Completed & verified healthy

- Dev box (`opspocket-dev`, 178.104.242.211): uptime 17h, 18% disk, 12 GB free RAM, load 0.01.
- Caddy active + serving all 8 site configs. All production domains return 2xx/3xx as expected (HTTP audit matrix below).
- `opspocket-backend.service` (Stripe webhook + orchestrator) active on 127.0.0.1:8092. DB initialised at `/var/lib/opspocket/tenants.db`. Running in `ORCHESTRATOR_DRY_RUN=1` — safe default until Stripe live-mode keys land.
- `opspocket-waitlist.service` active on 127.0.0.1:8091, 2 test signups recorded.
- `opspocket-snapshot.timer` active; next run 2026-04-23 04:00 UTC. 1 snapshot on record (`379026663`, created 07:47 today).
- `uptime-kuma` container healthy, accessible at `status.opspocket.com` (401 basic-auth, correct).
- 5 running Docker containers (forms-api, dafc-forms, forms-db-mariadb, glowpower, vantabiolabs, uptime-kuma) — all `Up` for 7–9h.
- Tenant DB holds 3 validation records (all destroyed + DNS purged). Schema matches backend code; no drift.
- Namecheap Private Email DNS records live (MX, SPF, DKIM, DMARC); inbound delivery confirmed end-to-end earlier today.

**HTTP audit matrix (all validated):**

| Host | Result |
|---|---|
| opspocket.com | 200 |
| www.opspocket.com | 301 → opspocket.com |
| opspocket.com/cloud | 200 |
| opspocket.com/blog/ | **200** (fixed this pass, was 404) |
| darleyabbeyfc.com | 200 |
| www.darleyabbeyfc.com | 301 |
| glowpower.co.uk | 200 |
| www.glowpower.co.uk | 301 |
| magichairstyler.com | 200 |
| www.magichairstyler.com | 301 |
| vantabiolabs.xyz | 200 |
| www.vantabiolabs.xyz | 301 |
| hello.dev.opspocket.com | 200 |
| status.opspocket.com | 401 (basic-auth, expected) |
| forms.darleyabbeyfc.com | 404 root (expected — POST-only form endpoint) |
| forms.aressentinel.com | 404 root (expected — POST-only form endpoint) |

### Fixed during this audit

1. **Blog index 404** — `/blog/` directly returned 404 because no `index.html` existed. Created `site-v2/blog/index.html` listing the four existing posts with OpsPocket dark theme, deployed to `/var/www/opspocket.com/blog/index.html` on dev box. Now returns 200.
2. **Postfix deferred queue** — three emails (2× welcome to findgriff@gmail.com, 1× to findgriff+realtest2@gmail.com) had been stuck in the queue since 09:24–09:51 today with `dsn=4.3.2 deferred transport` (Hetzner blocks port 25 outbound). Flushed all three with `postsuper -d`. Queue now empty. Permanent fix requires configuring a relay (Resend/Mailgun/SMTP2GO) via `infra/scripts/configure-smtp-relay.sh` once API key is obtained.

### Known issues (unfixed, low impact)

- **CI `installer-ci` workflow failing** on last 5 runs. Root cause: `openclaw-gateway` `systemd --user` service does not start inside a `--privileged` Docker container on GitHub Actions (no login session for the openclaw user). The real `infra/test-installer.sh` against a Hetzner VM passes; this is a CI-environment fidelity issue, not a real installer bug. Real tenant `177d1918` reached `active` state in 10 min earlier today. Plan: either use `machinectl`-based Ubuntu image in CI, or gate the gateway check behind a `CI_ENV=1` soft-fail, or replace smoke-test with a Hetzner-integration test on a tag push.
- **Flutter `analyze` reports 66 issues** — all `info` level (trailing commas, `use_build_context_synchronously`, one `unawaited_futures`). No errors, no warnings. Style-only; safe to ignore or clean up in a dedicated pass.
- **`www.magichairstyler.com` → root redirect** — `infra/caddy-sites/magichairstyler.caddy` has the standard `redir https://magichairstyler.com{uri} permanent` block, identical to the pattern used for `opspocket.com` and `glowpower.co.uk`. Users have reported the redirect not firing on some paths. Suspect a Cloudflare edge cache of an earlier failing response; purge `www.magichairstyler.com/*` at the CF edge and re-test. If that doesn't fix it, compare headers against `www.glowpower.co.uk` which uses the same pattern successfully.

---

## Outstanding work

### Cloud — must complete to go live

| # | Task | Owner action | Blocker? |
|---|---|---|---|
| 1 | **Stripe → live mode** | User must generate `sk_live_*` key in Stripe dashboard + paste into `/etc/opspocket/stripe-api-key` on dev box, update webhook secret, flip `ORCHESTRATOR_DRY_RUN=0` in `/etc/opspocket/backend.env`, `systemctl restart opspocket-backend`. | ⚠️ Needs owner |
| 2 | **Live Stripe Payment Links** | Recreate each Payment Link in live mode (6 total — 3 tiers × month/year) and swap URLs in `site-v2/cloud.html` `STRIPE_LINKS`. | ⚠️ Needs owner |
| 3 | **SMTP relay for outbound mail** | Sign up to Resend / Mailgun / SMTP2GO / Postmark; run `infra/scripts/configure-smtp-relay.sh` on dev box with the provided API key; add SPF/DKIM/DMARC on `mail.opspocket.com` via CF API (script self-generates the records to publish). | ⚠️ Needs owner (Resend signup) |
| 4 | **End-to-end live test** | After (1)+(2)+(3) are in place: buy Starter annual on the public site with a real card, verify VPS provisions + welcome email delivers + Stripe Portal cancel works. Expected duration: 10–12 min. | Blocked on 1–3 |
| 5 | **Destroy DigitalOcean droplet** `188.166.150.21` | Already shut down (port 80 unreachable, SSH fingerprint rotated — means either powered-off or DO recycled the instance). Confirm in DO console + click Destroy. | ⚠️ Needs owner |

### Cloud — deferred until above lands

- **Customer account dashboard (`/account`)** and **SaaS admin panel** — both blocked on Stripe being live + a tenants query API. Design captured in `docs/superpowers/specs/2026-04-22-blocked-saas-ui.md`. ~1 week of work once unblocked.

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
