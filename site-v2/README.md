# opspocket.com — production site (source of truth)

The live site served at **https://opspocket.com**. Hand-rolled HTML + CSS + JS
(no framework), migrated from the old DigitalOcean droplet to our Hetzner
dev box on 2026-04-22.

## Structure

```
site-v2/
├── index.html         # Homepage — hero, features, pricing (app), blog, FAQ
├── cloud.html         # NEW — Cloud pricing tiers, comparison, FAQ, waitlist CTA
├── blog/              # 4 posts (migrated verbatim from DO box)
│   ├── mission-control.html
│   ├── getting-started-ssh.html
│   ├── marketing-pipeline.html
│   └── the-bridge.html
└── images/            # hero, logo, feature screenshots
```

## Changes from the original DO-hosted version

- **index.html:** added `Cloud` link in nav + mobile menu, new "Managed Cloud"
  band between hero and ticker, extended schema.org `Offer` array with six
  Cloud tier entries.
- **cloud.html:** new — hand-rolled in the same visual language as `index.html`.
  Pricing grid with monthly/annual toggle, how-it-works, features, competitor
  comparison, FAQ, waitlist modal.
- Blog posts, images, favicons: unchanged.

## Pricing

| Tier | Monthly | Annual | App bundled? |
|---|---|---|---|
| Starter | £15.99/mo | £176.59/yr (8% off) | ✅ **Free with annual only** |
| Pro | £22.99/mo | £234.50/yr (15% off) | ✅ Always |
| Agency | £34.99/mo | £356.90/yr (15% off) | ✅ Always |

See `docs/superpowers/specs/2026-04-22-opspocket-site-migration-design.md`
for the design rationale.

## Deploying

```bash
# From the repo root:
rsync -a --delete site-v2/ dev:/var/www/opspocket.com/
ssh dev 'systemctl reload caddy'
```

Zero build step. File changes go live on the next request.

## Waitlist

POST to `/api/waitlist` appends to `/var/lib/opspocket/waitlist.txt` on the
dev box. Implementation: `infra/waitlist-server.py` (tiny Python HTTP server
behind Caddy, managed by `infra/opspocket-waitlist.service`).

To read waitlist signups:

```bash
ssh dev 'cat /var/lib/opspocket/waitlist.txt'
```

## Backups

The pre-migration state is preserved on the dev box at
`/var/www/opspocket.com/index.html.bak.<epoch>` plus rsynced copies on the
old DO droplet (`188.166.150.21:/root/opspocket_landing_page.old/`) — the
droplet stays up until other services are migrated separately.
