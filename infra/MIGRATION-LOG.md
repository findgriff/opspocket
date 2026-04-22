# DigitalOcean → Hetzner migration log

**Date:** 2026-04-22
**From:** DigitalOcean droplet `188.166.150.21` (Dokku PaaS, London, 25 GB disk)
**To:** Hetzner dev box `opspocket-dev` / `178.104.242.211` (CX43, Nuremberg, 160 GB)

## Sites migrated

All 6 production sites off DO are now running on the dev box with their
own Let's Encrypt certs via Cloudflare DNS-01.

| Site | Domain(s) | Deploy style on dev box | Status |
|---|---|---|---|
| dafc | darleyabbeyfc.com, www | Static files in `/var/www/darleyabbeyfc.com/` | ✓ 200 |
| dafc-forms | forms.darleyabbeyfc.com | Docker container, 127.0.0.1:5102 | ✓ |
| forms-api | forms.aressentinel.com | Docker container + MariaDB | ✓ |
| glowpower | glowpower.co.uk, www | Docker container, 127.0.0.1:5100 | ✓ 200 |
| magichairstyler | magichairstyler.com, www | Static files in `/var/www/magichairstyler.com/` | ✓ 200 |
| vantabiolabs | vantabiolabs.xyz, www | Docker container, 127.0.0.1:5101 | ✓ 200 |

## DNS changes (via Cloudflare API)

9 A records updated from old DO IP (`188.166.150.21`) to new dev box IP
(`178.104.242.211`). `www.glowpower.co.uk` is a CNAME, left in place.
All remain Cloudflare-proxied (orange cloud).

## Key learnings + gotchas

### 1. Dokku/herokuish images need `/start web` override

The saved Dokku images have CMD `/build` (the buildpack build step),
which crash-loops on re-run. Every dynamic app needed:

```
docker run ... <image> /start web
```

…as the explicit command. Some also needed `-e PORT=5000` because the
app's nginx config templates port from that env var.

### 2. `CLOUDFLARE_API_TOKEN` changes need `systemctl restart`, not `reload`

Systemd only re-reads `EnvironmentFile` on restart. `reload` (SIGHUP)
keeps the old env. This burned ~20 min of wondering why ACME DNS-01
was failing with "expected 1 zone, got 0" on domains the token clearly
owned — the old in-memory token was opspocket.com-scoped.

### 3. Herokuish bakes env vars into `/app/.profile.d/01-app-env.sh`

On restore via `docker save`/`docker load`, the baked env vars from
the old Dokku config get loaded AFTER `--env-file`, overriding it.
For forms-api this meant DATABASE_URL kept pointing at the old Dokku
MariaDB hostname. Fix: build a thin overlay image that rewrites the
baked env file.

### 4. DO droplet was at 94% disk → had to stream `docker save` direct

`docker save | gzip > /tmp/file` would fill up. Fix: SSH-pipe
`docker save | gzip` straight to the dev box — no intermediate
storage on the cramped source host.

### 5. fail2ban bans after multiple sshpass attempts

Early subagents spawning fresh sshpass connections tripped fail2ban on
the DO box, banning our Mac's IP. Fix: install our SSH pubkey on DO once
(via one authorised sshpass call) so all subsequent ops are key-based.

## Cutover sequence that worked

1. Add dev-box SSH pubkey to DO `authorized_keys` (once, via password).
2. Stream all 4 Docker images + 2 static tarballs + DB dump from DO →
   dev box in one SSH session. Total ~2 GB.
3. Dispatch 6 parallel subagents — each works only on dev box, handles:
   loading image, cleaning env file, running container, writing one
   `Caddyfile.d/*.caddy` block, reloading Caddy.
4. Verify cert issuance via `journalctl -u caddy | grep "certificate obtained"`.
5. Flip all 10 A records via Cloudflare API.
6. Verify public-facing HTTPS.

## DO droplet destruction — DO NOT destroy yet

The user will destroy `188.166.150.21` manually once they've confirmed:
- All 6 sites are stable on dev box for a few days
- Any other (not-yet-known) services on DO have been handled

For now, leave the DO droplet alive as a deeper rollback. Cost: ~$6/mo.

## Rollback

Per-site rollback (if one app misbehaves): update the A record back to
`188.166.150.21` via Cloudflare API. The old app is still running there.

Full rollback: flip all 10 A records back to `188.166.150.21`.

## Artifacts retained on dev box

```
/root/migration-artifacts/
├── dafc-static.tar.gz       (9 MB)
├── dafc-forms.env.raw
├── dafc-forms.tar.gz        (484 MB)
├── forms-api.env.raw
├── forms-api.tar.gz         (485 MB)
├── forms-db.sql.gz          (675 KB — MariaDB full dump)
├── glowpower.env.raw
├── glowpower.tar.gz         (385 MB)
├── magichairstyler-static.tar.gz (15 MB)
├── vantabiolabs.env.raw
└── vantabiolabs.tar.gz      (653 MB)
```

Total ~2 GB. Keep for 7 days as rollback. Delete with:

```
ssh dev 'rm -rf /root/migration-artifacts'
```

## Database root password for forms-db MariaDB

Stored at `/root/forms-db-root.txt` on dev box (mode 0600). Do NOT
commit. If it needs to be rotated, use `ALTER USER 'root'@'%' IDENTIFIED BY 'new'`
inside the container and update `DATABASE_URL` in the forms-api env
file + rebuild the overlay image.
