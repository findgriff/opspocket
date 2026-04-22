# OpsPocket.com Migration + Cloud Pricing Design

**Date:** 2026-04-22
**Goal:** Recover the original hand-rolled opspocket.com site (currently on a DigitalOcean droplet) onto the new Hetzner dev box, add a `/cloud` pricing page and a "Managed Cloud" section on the homepage, without regressing the visual design the user loves.

---

## Context

### What's currently live

- **DNS:** `opspocket.com` → Cloudflare → `178.104.242.211` (our new CX43 dev box in Nuremberg). Cloudflare proxy is ON (orange cloud).
- **Outcome:** HTTP 525 error. Cloudflare reaches the dev box but can't TLS-handshake because Caddy on the dev box only has `*.dev.opspocket.com` and `hello.dev.opspocket.com` in its Caddyfile — nothing for `opspocket.com`.
- **Net:** the public site is effectively down.

### What's on the old DO droplet

- **IP:** `188.166.150.21` (Dokku-based droplet, London)
- **Path:** `/root/opspocket_landing_page.old/`
- **Content:** hand-rolled static HTML:
  - `index.html` — 1578 lines, all inline CSS/JS, full SEO (Open Graph, schema.org, canonical tags)
  - `blog/*.html` — 4 posts (mission-control, marketing-pipeline, getting-started-ssh, the-bridge)
  - `images/` — hero, feature screenshots, logo
  - `.git/` — old git history preserved
- **Already mirrored locally** to `/tmp/opspocket-original/` via rsync.
- **Note:** the droplet hosts other unrelated sites. The user will kill it manually when those are migrated — we don't touch it in this work.

### Gap to fill

- The hand-rolled site currently markets only the iOS app (£8.50/mo).
- No `/cloud` page.
- No mention of managed hosting anywhere.
- User wants to preserve the feel of the original 100% (they didn't like the Next.js version I shipped in a previous session).

---

## Architecture

### One box, multiple hostnames

The dev box (CX43, Nuremberg) serves all of these from a single Caddy instance, routing by hostname:

| Hostname | Docroot / target | Notes |
|---|---|---|
| `opspocket.com` | `/var/www/opspocket.com/` (static HTML) | Public site, Cloudflare proxied |
| `www.opspocket.com` | 301 redirect to `opspocket.com` | Cloudflare proxied |
| `stage.opspocket.com` | `/var/www/opspocket.com-stage/` | For reviewing changes before going live |
| `*.dev.opspocket.com` | existing test-tenant harness | Untouched |
| `hello.dev.opspocket.com` | existing health page | Untouched |

### TLS

All hostnames get real Let's Encrypt certs via Caddy. We already have the Cloudflare DNS-01 plugin installed on the dev box (used for the existing `*.dev.opspocket.com` wildcard), so the same `CLOUDFLARE_API_TOKEN` env file issues certs for the new hostnames automatically. DNS-01 works even when Cloudflare proxy is ON for opspocket.com.

### Staging strategy

Stage and prod are just two directories on disk. Both are served by Caddy. To go live:

```
rsync -a /var/www/opspocket.com-stage/ /var/www/opspocket.com/
```

To roll back (if something breaks):

```
rsync -a /var/www/opspocket.com-backup/ /var/www/opspocket.com/
```

We keep a timestamped backup every time we push stage → live.

---

## What changes vs what stays

| Component | Action |
|---|---|
| Original `index.html` hero, fonts, colours, animations | **Keep verbatim** |
| Navigation bar | Add one link: `Cloud` (sits between existing links) |
| Homepage "Managed Cloud" band | **New** — single section inserted below the existing hero, links to `/cloud` |
| `/cloud` page | **New** — full tier grid, comparison vs competitors, FAQ |
| `/app` page (if exists on current origin) | No change |
| Blog (`/blog/*.html`, all 4 posts) | Preserved 1:1 |
| Blog in nav? | No — blog link lives in footer only, low-profile |
| Images, favicons, OG cards | Preserved 1:1 |
| SEO schema.org | Extend `@type: SoftwareApplication` offers array to include Cloud tiers |
| Footer | Add Cloud + pricing links |

---

## Cloud pricing tiers

All prices in GBP. Billing handled later (see "Sign-up CTA" below).

| Tier | Monthly | Annual | App bundled? | Annual saves |
|---|---|---|---|---|
| **Starter** | £15.99/mo | **£176.59/yr** (~£14.72/mo effective) | ✅ **Free with annual only** (worth £102/yr) | £117.29/yr |
| **Pro** | £22.99/mo | £234.50/yr (15% off) | ✅ Always included | £41.38/yr |
| **Agency** | £34.99/mo | £356.90/yr (15% off) | ✅ Always included | £62.98/yr |

**Starter monthly:** customers can buy the iOS app separately for £8.50/mo (existing App pricing).

**Starter annual's "free app" bundle** is the tier's unique selling point — £176.59 upfront for the full stack, designed to drive annual conversions and lock in 12-month retention.

### Specs per tier

| | Starter | Pro | Agency |
|---|---|---|---|
| vCPUs | 2 | 4 | 8 |
| RAM | 4 GB | 8 GB | 16 GB |
| Disk | 80 GB | 80 GB | 160 GB |
| Concurrent agents | 1 | Unlimited | Unlimited |
| Support | Community | Email | Priority + SLA |
| Hetzner type | CPX22 | CPX32 | CPX42 |

### Schema.org update

The existing schema on the homepage declares three `Offer` objects for the app (£8.50/£80/£120). We add six more for the Cloud tiers (Starter monthly/annual, Pro monthly/annual, Agency monthly/annual) and change `@type` to `"Product"` with `offers` array, so Google Shopping / search shows them properly.

---

## Homepage "Managed Cloud" band

Inserted as a new `<section>` between the existing hero and the next existing section. Single band, same dark palette, one cyan accent, one red CTA button.

Layout (text mockup):

```
──────────────────────────────────────────────────────────────
   ⚡ NEW · MANAGED CLOUD · FROM £15.99/MO

   Don't want to run your own VPS?
   OpsPocket Cloud is OpenClaw, managed — one URL, one
   password, no Docker, no DevOps.

   [ See Cloud plans → ]
──────────────────────────────────────────────────────────────
```

- Height: ~180 px on desktop, collapses cleanly on mobile
- "NEW" eyebrow in the cyan monospace tracking used elsewhere on the site
- Body text in the same Inter weight the rest of the site uses
- Single CTA — `/cloud`, styled like existing red buttons

---

## `/cloud` page structure

Same hand-rolled HTML/CSS style as `index.html`. No framework. Sections in order:

1. **Hero** — "OpenClaw in the cloud, managed for you"
   - Subhead: "No DevOps. No Docker. Just open the URL."
   - Two CTAs: `[Get Started →]` (scrolls to pricing), `[See the App →]` (→ `/app`)

2. **Pricing grid** — 3 columns (Starter / Pro / Agency) with monthly/annual toggle. Each card includes:
   - Tier name + tag ("Best value" on Starter annual, "Most popular" on Pro)
   - Price (£X.XX/mo or £X/yr)
   - Feature list (6 bullets per tier)
   - Sign-up CTA

3. **How it works** — 3-step illustrated strip:
   - "1. Sign up" → "2. We provision your VPS (2 min)" → "3. Open the URL + chat"

4. **What's included** — 6-tile feature grid:
   - Fully managed OpenClaw
   - Mobile app (annual Starter / always Pro+)
   - Daily backups
   - Auto-updates
   - EU data residency
   - Email / SLA support (by tier)

5. **Competitor comparison** — 3-column table:
   - OpsPocket Cloud vs xCloud vs MyClaw.ai
   - Rows: price, mobile app, EU hosting, support SLA, free tier

6. **FAQ** — 6–8 questions:
   - "What happens if I cancel?"
   - "Can I upgrade/downgrade?"
   - "Where is my data hosted?"
   - "Do you store my OpenAI keys?"
   - "What if I outgrow the tier?"
   - etc.

7. **Footer CTA** — "Any questions? Email hello@opspocket.com"

---

## Sign-up button behaviour

Cloud isn't ready to sell today — we need Stripe first. For now, the "Get Started" CTA does:

- Opens an inline email-capture form ("Join the waitlist — we'll email you when Cloud goes live")
- Email posts to a simple endpoint on the dev box: `POST https://opspocket.com/api/waitlist`
- Endpoint is a tiny Caddy-served CGI-style script that appends to `/var/lib/opspocket/waitlist.txt` (plain file, one email per line)
- Success: "Thanks — we'll be in touch soon"

Swap to Stripe Checkout later by changing the form action URL. No frontend rewrite needed.

---

## Caddy config changes

Adds three new site blocks to the existing `/etc/caddy/Caddyfile`:

```
opspocket.com, www.opspocket.com {
    tls {
        dns cloudflare {env.CLOUDFLARE_API_TOKEN}
    }
    @www host www.opspocket.com
    redir @www https://opspocket.com{uri} 301

    root * /var/www/opspocket.com
    file_server
    try_files {path} {path}.html {path}/index.html =404

    # Tiny waitlist endpoint — bash script writes to plain file
    handle /api/waitlist {
        reverse_proxy 127.0.0.1:8091
    }
}

stage.opspocket.com {
    tls {
        dns cloudflare {env.CLOUDFLARE_API_TOKEN}
    }

    # HTTP basic-auth so only we can see stage
    basic_auth {
        stage {env.STAGE_BASIC_AUTH_HASH}
    }

    root * /var/www/opspocket.com-stage
    file_server
    try_files {path} {path}.html {path}/index.html =404
}
```

Existing `hello.dev.opspocket.com` and `*.dev.opspocket.com` blocks stay exactly as they are.

---

## File layout on dev box

```
/var/www/
  opspocket.com/                ← live site
    index.html
    cloud.html
    app.html        (if on origin)
    404.html
    _headers        (optional; Caddy doesn't use but harmless)
    images/
      hero.png
      feature-terminal.png
      ...
    blog/
      mission-control.html
      marketing-pipeline.html
      getting-started-ssh.html
      the-bridge.html

  opspocket.com-stage/          ← same shape as above
  opspocket.com-backup-<ts>/    ← rotating backups, cleaned after 7 days

/var/lib/opspocket/
  waitlist.txt                  ← append-only list of signup emails
```

---

## Waitlist endpoint (tiny and local)

A ~30-line bash CGI script lives at `/usr/local/bin/opspocket-waitlist`, invoked by a minimal HTTP server on port 8091:

```bash
#!/usr/bin/env bash
# POST /api/waitlist  body: email=foo@bar.com
read -r body
email=$(echo "$body" | sed -n 's/^email=//p' | head -1)
# naive email validation
if [[ ! "$email" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; then
  printf 'HTTP/1.1 400 Bad Request\r\n\r\n{"error":"bad email"}'
  exit
fi
echo "$(date -u +%FT%TZ) $email" >> /var/lib/opspocket/waitlist.txt
printf 'HTTP/1.1 200 OK\r\nContent-Type: application/json\r\n\r\n{"ok":true}'
```

Invoked by a systemd socket unit (`socat` or `inetd`-style). Zero dependencies beyond what's already on the box.

---

## Migration steps (high-level; details in the plan)

1. Stage setup:
   - Add `stage.opspocket.com` A record in Cloudflare (grey-cloud for DNS-01 to work without CF-proxy interference)
   - Rsync `/tmp/opspocket-original/` → `dev:/var/www/opspocket.com-stage/`
   - Add stage block to Caddyfile
   - Test: `https://stage.opspocket.com` returns original site with cert
2. Content changes (on staged copy):
   - Edit `index.html` — add homepage "Managed Cloud" band, update nav
   - Create `cloud.html` — new `/cloud` page per spec
   - Update SEO schema
3. Waitlist endpoint:
   - Install bash script + systemd socket unit
   - Verify `curl -X POST https://stage.opspocket.com/api/waitlist -d email=x@x.com` appends to file
4. User review:
   - User visits `stage.opspocket.com` → approves or requests changes
   - Fix in-place and re-review
5. Cutover:
   - `rsync -a /var/www/opspocket.com-stage/ /var/www/opspocket.com/`
   - Add `opspocket.com` block to Caddyfile
   - `systemctl reload caddy`
   - Cloudflare purge cache
   - Verify `https://opspocket.com` returns 200
6. Monitor for 24 h

---

## Rollback plan

If cutover breaks anything:

```
rsync -a /var/www/opspocket.com-backup-<latest>/ /var/www/opspocket.com/
systemctl reload caddy
```

That's 10 seconds. We keep the DigitalOcean origin alive for 7 days after cutover as a deeper fallback (user handles killing it separately).

---

## What this does NOT include (YAGNI scope cut)

- Stripe integration — waitlist first, Stripe comes when we have signups to act on
- Admin dashboard to see waitlist — just `cat /var/lib/opspocket/waitlist.txt` for now
- Customer login / account page — not needed until we have paying customers
- New blog posts — we migrate the existing 4 unchanged; new content is a separate cycle
- Visual redesign of `index.html` itself — preserving the existing hand-crafted style is a hard requirement
- Migration of the other websites on the DO droplet — user will handle those manually

---

## Success criteria

- `https://opspocket.com` returns 200 with a valid Let's Encrypt cert
- Hero, colours, animations, blog posts all match the original bit-for-bit (viewable via side-by-side diff of rendered HTML)
- New `Cloud` nav link leads to `/cloud` page showing correct pricing
- Homepage has the new "Managed Cloud" band between hero and the next section
- Waitlist form accepts an email and writes to `/var/lib/opspocket/waitlist.txt`
- `https://stage.opspocket.com` is behind HTTP basic auth (only we see it)
- All existing blog post URLs still resolve (e.g. `opspocket.com/blog/mission-control.html`)
- SEO tags + schema.org render correctly (validate with [schema.org validator](https://validator.schema.org/))
- Rollback path tested at least once during stage phase

---

## Open risks / trade-offs

- **Hand-editing a 1578-line HTML file** — the original is one big file. Adding a section and updating nav is surgical but the file becomes 1700 lines. Acceptable for now; future refactor could split into `_head.html` / `_nav.html` / `_hero.html` / etc with a simple concatenation step at deploy. Not worth doing today.
- **Cloudflare proxy interaction** — we keep CF proxy ON for opspocket.com (DDoS, CDN, IP hiding). DNS-01 cert issuance works regardless. If anything misbehaves mid-migration we can temporarily flip to grey-cloud and restore after.
- **Bash waitlist endpoint is deliberately primitive** — no rate limiting, no captcha, no deduplication. If spam becomes a problem we add basic bot protection. Until we have Cloud traffic, it won't be.
- **Same-box staging + production** — if someone DDoS's opspocket.com, stage might also suffer (shared CPU). Acceptable at this scale; will split when we have real customer traffic.
