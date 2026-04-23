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

# CLAUDE.md — OpsPocket Agent Operating Instructions

You are the next Claude agent on the OpsPocket project. **Read `HANDOVER.md` first** for full project state. This document is your operating manual — what to do, what not to do, how the environment works.

**Accuracy contract — use this in every response:**
- ✅ Verified — directly observed or ran this session
- 🟡 Likely — reasonable inference from available context
- ❓ Unknown — must be checked before acting on it

Never state speculation as fact. If you don't know, say so and verify.

---

## 1. Project context + objective

**Project:** OpsPocket — iPhone app for managing VPSes + managed OpenClaw Cloud hosting SaaS.

**Current objective** (2026-04-23, unless owner changes it):
1. Keep the Cloud platform shippable — a real customer could buy today, VPS provisions, welcome email delivers
2. Build the app pairing handler so welcome-email-tap → app auto-configured
3. Get the iPhone app to TestFlight

The iPhone app is **shelved for public release** as a business priority — but still actively developed because the pairing flow + TestFlight ship are near-term.

**Bundle ID:** `co.opspocket.opspocket`
**Flutter:** 3.41.7 / Dart 3.11.5 ✅
**Apple Team ID:** `RT2UR47KNW` ✅
**Repo:** `git@github.com:findgriff/opspocket.git` ✅
**Branch that all work lands on:** `main` ✅

---

## 2. How to behave

- **Read before editing.** Never propose changes to a file you haven't read. Use the Read tool liberally.
- **Verify before claiming.** If you say "the tests pass", you just ran `flutter test`. If you say "it's deployed", you just SSH'd and confirmed.
- **Announce uncertainty.** Mark ❓ next to anything you infer but didn't confirm.
- **Prefer small commits.** Each commit should describe one change with a `type(scope): subject` message (see §5).
- **Never invent credentials.** Secrets live on the dev box under `/etc/opspocket/` + `/root/`. If you need one, reference the file by path and let it load at runtime.
- **Never push to `main` a build that fails `flutter analyze` or `flutter test`.** Those are the two gates.
- **Be blunt about what didn't work.** "I tried X, it failed because Y, here's what I did instead." — is always better than "I fixed it" when you didn't fully.
- **Respect existing patterns.** Riverpod `StateNotifierProvider.family`, the `SshClient` abstraction, `AppTheme.*` colours, `SecretKeys` key naming — these are established. Extend, don't replace.

---

## 3. Tools + environments available

Assume these exist; verify with `which` or equivalent if unsure:

### On Craig's Mac (your primary workstation)

- macOS (15+ / 26.x)
- Flutter 3.41.7, Dart 3.11.5, Xcode 26.x — ✅ verified this session
- `git` + `gh` (GitHub CLI, authenticated as `findgriff` 🟡)
- `rsync`, `scp`, `ssh` — standard — ✅
- `xcrun devicectl` for physical-device install
- `python3` stdlib
- `curl`, `jq` probably

### Remote environments you have access to

- **Dev box** (Hetzner) at `ssh dev` — Ubuntu 24.04, root access; see §4
- **GitHub** — push/pull access to `findgriff/opspocket`; `gh` is authenticated 🟡
- **Cloudflare API** — token lives on dev box, not on Mac; use from dev box
- **Hetzner API** — same — token on dev box
- **Stripe API** — live mode secret key on dev box; never include value in code
- **Resend API** — sending-only key on dev box

### Tools you DO NOT have

- Apple App Store Connect (needs Craig's login + 2FA)
- Stripe dashboard (needs Craig's login + 2FA)
- Cloudflare dashboard (API token works for DNS operations from dev box; purge-cache permission is NOT on the current token)

---

## 4. Dev box access + usage

**Hostname:** `opspocket-dev`
**IP:** `178.104.242.211` ✅
**User:** `root`
**Shortcut:** `ssh dev` — configured in Craig's Mac `~/.ssh/config`, uses `~/.ssh/id_ed25519`

### Standard operations

```bash
# Run any command on the dev box
ssh dev 'uptime'
ssh dev 'systemctl status opspocket-backend --no-pager'

# Deploy backend code
rsync -a infra/backend/ dev:/opt/opspocket/backend/
ssh dev 'systemctl restart opspocket-backend'

# Deploy marketing site
rsync -a --delete site-v2/ dev:/var/www/opspocket.com/
ssh dev 'systemctl reload caddy'

# Deploy Caddy site configs
scp infra/caddy-sites/<app>.caddy dev:/etc/caddy/Caddyfile.d/<app>.caddy
ssh dev 'systemctl reload caddy'           # NOT restart — reload is cheaper

# Rotate Cloudflare API token in Caddy (edge case — requires restart)
ssh dev 'vim /etc/caddy/cloudflare.env && systemctl restart caddy'
# ⚠ systemctl RELOAD does not re-read EnvironmentFile — must be restart

# Tail backend logs
ssh dev 'journalctl -u opspocket-backend -f'

# Query tenant DB
ssh dev 'sqlite3 /var/lib/opspocket/tenants.db "SELECT id, tier, status FROM tenants;"'
```

### Files owned by the Cloud platform (don't touch without cause)

```
/etc/opspocket/                    — all secrets (0600)
  stripe-api-key                   — sk_live_*
  stripe-webhook-secret            — whsec_*
  resend-api-key, email-resend-key — re_* (sending)
  hetzner-token                    — Hetzner Cloud API
  cloudflare-token                 — CF API for orchestrator DNS writes
  admin-creds.txt                  — admin/*/plaintext (rotate via caddy hash-password)
  stripe-ids.env, stripe-links.env — Stripe product/price/link IDs
  backend.env                      — service env (DRY_RUN flag lives here)

/etc/caddy/Caddyfile.d/*.caddy     — per-site Caddy configs (sourced from repo)
/etc/caddy/cloudflare.env          — CF token for DNS-01 (separate from orchestrator token)
/etc/pam.d/su                      — modified this session (pam_wheel trust for sudo group)
/etc/passwd + /etc/shadow          — modified this session (added apptest, clawd alias)

/opt/opspocket/backend/            — app.py + api_extras.py + sync_*.py + schema.sql
/var/lib/opspocket/tenants.db      — 19-table SQLite — CRM + Stripe cache + Hetzner cache + audit
/var/lib/opspocket/waitlist.txt    — waitlist signups
/var/www/opspocket.com/            — static site

/root/.ssh/authorized_keys         — Craig's Mac pubkey + orchestrator pubkey
/root/tenants.json                 — tenant registry (also in repo as infra/tenants.json)
/root/.hetzner-token               — legacy fallback; preferred loc is /etc/opspocket/
/root/CREDENTIALS.json             — dev box's OWN OpenClaw creds (clawmine user)
```

### Systemd services you may interact with

```
caddy.service                     — reverse proxy + TLS
opspocket-backend.service         — Stripe webhook + orchestrator + CRM API (port 8092)
opspocket-waitlist.service        — tiny waitlist endpoint (port 8091)
opspocket-snapshot.timer          — daily Hetzner snapshot at 04:00 UTC
docker.service                    — runs Kuma, MariaDB, migrated legacy sites
```

---

## 5. GitHub + commit conventions

### Repo

`git@github.com:findgriff/opspocket.git` — ✅ verified this session via `git remote -v`.

### Clone

```bash
gh auth status                                   # confirm CLI auth
git clone git@github.com:findgriff/opspocket.git
cd opspocket
git checkout main
```

### Push / PR flow

- Work lands directly on `main` in recent history — no feature branches have been used this week
- You may still open PRs if the change is large or risky; use `gh pr create` with a detailed body
- Never `push --force` to `main`

### Commit style (verified from recent history)

Use Conventional-Commits-ish prefixes that match existing commits:

```
feat(cloud): ...
feat(site): ...
feat(mission-control): ...
fix(backend): ...
fix(installer): ...
fix(site): ...
chore(audit): ...
refactor(mission-control): ...
test(tunnel): ...
docs: ...
```

Examples of good subjects (from `git log`):
- `feat(crm): full SaaS CRM v2 — Stripe+Hetzner sync, tenant drawer, analytics`
- `fix(site): ticker is now a single flowing announcement, not bullet list`
- `refactor(mission-control): delete native reskin, tunnel to server-side UI`

Always include a body explaining *why*, not just what. End with the Co-Authored-By line (for session continuity):

```
Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
```

### Don't

- Don't amend `origin/main` history (force-push off)
- Don't commit files under `/etc/`, `/root/`, or any `stripe-*` / `resend-*` / `cloudflare-*` file
- Don't commit `build/`, `.dart_tool/`, `Pods/`, `*.g.dart` that should be generated

---

## 6. How to continue development safely

### Before ANY code change

1. `git status` — expect clean working tree
2. `git log -1 --oneline` — match what `HANDOVER.md` says the tip is
3. Decide if the change is a feature / fix / refactor
4. Create a TodoWrite list if >3 steps
5. Read every file you'll touch

### While developing

- Edit → run `flutter analyze` on changed scope
- Write/update tests in `test/` — every new provider, notifier, or pure function gets a test
- Run `flutter test` for the full suite
- For UI changes, install on the physical iPhone to verify

### Before every commit

- `flutter analyze` — zero errors, zero warnings (info-level is fine)
- `flutter test` — all tests pass
- `xattr -cr .` — clear xattrs (macOS chore)
- `flutter build ios --release` — confirm a release build compiles

### High-risk areas — think twice

- **`lib/shared/storage/secure_storage.dart`** — renaming a `SecretKeys` method breaks every existing user's Keychain entries on upgrade
- **`lib/features/command_templates/data/builtin_templates.dart`** — never mutate an existing builtin ID; add new IDs only
- **`lib/features/ssh/domain/ssh_client.dart`** — every feature depends on this interface
- **`ios/Runner/Info.plist`** — bundle ID, URL schemes, required modes
- **`ios/Runner.xcodeproj/project.pbxproj`** — DEVELOPMENT_TEAM must stay `RT2UR47KNW` for signing
- **`infra/backend/app.py` + `schema.sql`** — the backend is running live; schema changes need migrations (SQLite schema is forgiving but be careful)
- **`infra/caddy-sites/opspocket.caddy`** — typo takes the production site down; always `caddy validate` via `systemctl reload` test

---

## 7. Build + test commands (memorize)

### App (iPhone)

```bash
cd /Users/findgriff/Downloads/opspocket-main

# Toolchain check
flutter --version                                          # 3.41.7 stable

# Fresh pulls
flutter pub get
dart run build_runner build --delete-conflicting-outputs   # Drift + riverpod_generator

# Lint + test
flutter analyze                                            # must be clean
flutter test                                               # must be green

# Simulator
flutter run -d "iPhone 16"

# Physical device (release mode — reliable on iOS 26 wireless)
xattr -cr .                                                # clear Finder xattrs
flutter build ios --release                                # build → Runner.app
DEV=3F2D242C-9CAB-5374-998F-E6BD5D2DF79A                   # devicectl device id
xcrun devicectl device install app --device $DEV build/ios/iphoneos/Runner.app
xcrun devicectl device process launch --device $DEV co.opspocket.opspocket
```

### Backend (Cloud)

```bash
# Deploy
rsync -a infra/backend/ dev:/opt/opspocket/backend/
ssh dev 'systemctl restart opspocket-backend'

# Check
ssh dev 'journalctl -u opspocket-backend -n 30 --no-pager'

# Sync Stripe + Hetzner data into local cache
# Admin password is in dev box /etc/opspocket/admin-creds.txt — reference, do not embed
curl -sS -u "craig:<admin-pw>" -X POST https://opspocket.com/api/admin/sync/stripe
curl -sS -u "craig:<admin-pw>" -X POST https://opspocket.com/api/admin/sync/hetzner
```

### Installer smoke-test (takes 15 min, costs ~€0.10)

```bash
./infra/test-installer.sh             # spawns throwaway VM, runs installer, destroys
```

### Marketing site deploy

```bash
rsync -a --delete site-v2/ dev:/var/www/opspocket.com/
ssh dev 'systemctl reload caddy'       # no TLS needed, cheap reload
```

---

## 8. How to validate changes end-to-end

### For app changes

1. Release build + install on Craig's iPhone (§7 recipe)
2. Trust dev cert on phone if required
3. Walk through affected user journey: splash → unlock → server list → [your feature]
4. If SSH touched: confirm terminal returns `hostname`, quick-actions execute
5. If ClawGate touched: confirm OpenClaw UI loads in WebView after auth
6. If MC credentials touched: open Edit profile → Mission Control section → save → reopen → fields persisted

### For backend changes

1. Deploy with rsync + `systemctl restart`
2. Hit affected endpoint with `curl`
3. Check logs: `journalctl -u opspocket-backend -n 50 --no-pager`
4. Confirm DB mutation: `sqlite3 /var/lib/opspocket/tenants.db` + relevant SELECT
5. Confirm audit log entry created (if admin mutation): `curl -u craig:<pw> https://opspocket.com/api/admin/audit?limit=5`

### For site changes

1. rsync site-v2 to dev box
2. `curl -sS https://opspocket.com/<path>` — expect 200
3. Check raw HTML for your change (bypass Cloudflare cache if needed: `curl -H 'Cache-Control: no-cache'` or add `?v=<timestamp>`)
4. Browser: hard-refresh (`⌘+Shift+R`) or incognito

---

## 9. Expected audit process (at start of major task)

If the owner hands you a task bigger than a single change:

1. **Audit** — read relevant files, check git log, identify what exists vs. what's broken vs. what's missing
2. **Plan** — write a TodoWrite list with concrete steps
3. **Build** — one item at a time, committing between them
4. **Test** — `flutter test` + manual where applicable
5. **Document** — update `HANDOVER.md` if the project state moved
6. **Report** — summarize what shipped, what's still outstanding, any risks

Don't skip the audit. The first 10 minutes of reading save hours of undoing wrong assumptions.

---

## 10. Handling unfinished work

If the owner's context window runs out or they walk away:

- Commit what you have IF it compiles + tests pass — even if UX is half-finished
- Document the half-done state in `HANDOVER.md` under "Partially completed"
- Leave a TODO comment at the specific file + line explaining what's missing
- Never commit broken code to `main` — open a branch if the state is half-done

Example — a half-built file would have:

```dart
// TODO(next-agent): this widget currently shows stub data. Finish wiring
// to `ref.watch(realDataProvider)` + loading/error states. Blocked by
// the SftpSession.openSftp() stub in ssh_client.dart — restore that first.
```

---

## 11. How to update handover documents

When you end a session where the project state moved:

- Open `HANDOVER.md`
- Update §2 "Current status" to reflect what's now true
- Move items between §3 (completed) / §4 (partial) / §5 (broken) / §7 (TODO) as appropriate
- Bump §17 with any new commits
- Update this file (`CLAUDE.md`) if the operating environment changed

Don't rewrite the whole file from scratch unless the owner asks — it's accreted deliberately to give history. Add new sections at the top with dated headings; prune truly obsolete sections when they're safe to remove.

---

## 12. How to report progress

To the owner, always:

- Lead with what shipped (verbs: "deployed", "committed", "verified")
- Show evidence (commit SHA, test output, URL responses)
- Clearly separate "done" / "in progress" / "blocked"
- Flag risks with specific mitigations

Bad: "Fixed the pairing flow."
Good: "Added URL-scheme handler in `ios/Runner/Info.plist` commit `abc1234`, built pairing screen at `lib/features/pairing/pairing_screen.dart` (stub — doesn't yet fetch `/api/pair/<code>`, blocked on `SshClient` needing a pairing helper). Tests pass 82/82. Not yet installed on device."

---

## 13. How to continue if your context runs low

1. **Commit everything that's green** — even a half-finished feature, behind a TODO, is better than losing work
2. **Update `HANDOVER.md`** with the current state — what's partially done, what's next
3. **Write a final message** for the owner summarising where you are and what the next agent should do first
4. **Don't try to save one last thing** — if your context is near full, stop and hand off cleanly

---

## 14. Key technical constraints

- **Flutter / Dart versions are pinned** — don't upgrade without owner approval; Drift + riverpod_generator are version-sensitive
- **iOS deployment target** is high (iOS 13.0 per Pods); bumping needs Info.plist + pbxproj edits
- **No raw dartssh2 in feature code** — all SSH goes via `SshClient` interface
- **Keychain accessibility must stay `first_unlock_this_device`** — do not change to `whenUnlocked`, breaks locked-screen access
- **Python stdlib only on the Cloud backend** — no pip install; urllib / sqlite3 / http.server only
- **OpsClaw palette** — red `#FF3B1F`, cyan `#00E6FF`, black `#0A0A0B`; always via `AppTheme.*`
- **Caddy config must be valid** — `caddy validate` before reload; a broken config takes down the whole site
- **Hetzner blocks port 25 outbound** — all email goes via Resend API, not SMTP

---

## 15. Key product constraints

- **iPhone app is shelved for public release** — don't build App Store marketing flows without owner go-ahead
- **Per-VPS-per-customer Cloud architecture stays** until 5+ paying customers — don't pivot to shared-host without confirmation
- **Cloud pricing:** Starter £15.99/mo, Pro £22.99/mo, Agency £34.99/mo (annual -15%); refreshed in a recent discussion to potentially £9.99 / £19.99 / £39.99 — **verify with owner before changing live Stripe Payment Links**
- **OpenClaw 2026.4.5** is the target version — installer must handle this release; older versions are out-of-scope
- **Mission Control = server-side UI** — do not re-build a native reskin; any "Mission Control" UI is a tunneled WebView
- **Single founder operating the business** — prefer simple operational choices over complex ones

---

## 16. Priorities for the next agent

In rough order. Adjust based on owner direction.

### If the owner says "just keep the lights on"

- Monitor `opspocket.com` uptime (`status.opspocket.com` Kuma)
- Watch for Stripe webhooks failing or tenant provisioning timing out
- Keep daily snapshots running (`opspocket-snapshot.timer`)
- Answer support tickets via `/admin`
- No code changes unless a bug is reported

### If the owner says "keep shipping"

1. Run the first real Stripe live-card test purchase (owner action)
2. Build app pairing deep-link handler (see `HANDOVER.md` §7.1)
3. Restore SFTP/Files feature (see `HANDOVER.md` §4) — optional
4. Set up TestFlight distribution
5. Add analytics (optional but useful before scale)

### If the owner says "improve CRM"

- Per-tenant usage metrics pulled from the tenant's `~/.openclaw/` via scheduled SSH poller
- GDPR export + delete flow (schema table exists, no UI)
- Trigger Stripe sync automatically on webhook (currently admin has to press the button)
- Automated lifecycle emails (renewal reminder, trial ending, etc.)

### If the owner says "fix the CI"

- `installer-ci.yml` fails because systemd-user services don't start in privileged Docker
- Options: (a) use machinectl-based image, (b) soft-fail gateway check under `CI_ENV=1`, (c) replace with Hetzner integration test on tag push
- Real `infra/test-installer.sh` against a Hetzner VM passes, so there's no actual regression — it's a test-environment fidelity issue

---

## 17. Quick reference card

```
Repo         git@github.com:findgriff/opspocket.git
Branch       main (only branch in active use)
App path     /Users/findgriff/Downloads/opspocket-main
Bundle ID    co.opspocket.opspocket
Team         RT2UR47KNW
Flutter      3.41.7 / Dart 3.11.5
Xcode        26.2

Dev box      ssh dev    (178.104.242.211)
iPhone       xcrun devicectl  UDID 00008120-001A41693682201E
                              DEVID 3F2D242C-9CAB-5374-998F-E6BD5D2DF79A

Build app       flutter build ios --release
Install app     xcrun devicectl device install app --device $DEV build/ios/iphoneos/Runner.app
Launch app      xcrun devicectl device process launch --device $DEV co.opspocket.opspocket

Lint          flutter analyze
Test          flutter test

Deploy site   rsync -a --delete site-v2/ dev:/var/www/opspocket.com/ && ssh dev 'systemctl reload caddy'
Deploy bknd   rsync -a infra/backend/ dev:/opt/opspocket/backend/ && ssh dev 'systemctl restart opspocket-backend'

Logs          ssh dev 'journalctl -u opspocket-backend -f'
DB            ssh dev 'sqlite3 /var/lib/opspocket/tenants.db'

Admin         https://opspocket.com/admin
              craig / <pw from dev box /etc/opspocket/admin-creds.txt>
Account       https://opspocket.com/account  (magic-link auth)
Status        https://status.opspocket.com   (Kuma, basic-auth)

Known pain    iOS 26 wireless debug → black screen (use release + devicectl)
              Mac Downloads xattrs → build fails (xattr -cr . before building)
              Dev cert re-trust after reinstall (phone Settings → VPN & Device Mgmt)
              systemctl reload caddy does NOT re-read EnvironmentFile (restart instead)

Never         - Push broken code to main (must lint + test)
              - Invent credentials (always reference by file path)
              - Rename SecretKeys methods (breaks upgrades)
              - Change existing builtin template IDs (dupes entries in users' DBs)
              - Amend or force-push main
```

---

*When in doubt, read `HANDOVER.md` §18 "What to verify first" and run those commands. If any fail, fix the environment before writing code.*
