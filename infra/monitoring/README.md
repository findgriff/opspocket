# Monitoring — Uptime Kuma

Self-hosted uptime monitoring for OpsPocket production sites.

- **Host:** dev box (178.104.242.211, Hetzner CX43)
- **Public URL:** https://status.opspocket.com/ (basic-auth gated)
- **Container:** `uptime-kuma` (`louislam/uptime-kuma:1`)
- **Data volume:** `/var/lib/opspocket/uptime-kuma-data/` on dev box
- **Upstream bind:** `127.0.0.1:3001` (loopback only — Caddy fronts it)
- **Caddy site file:** `infra/caddy-sites/monitoring.caddy` (copy in `/etc/caddy/Caddyfile.d/monitoring.caddy` on dev box)

## Basic auth

Caddy edge requires HTTP basic auth before Uptime Kuma's own login screen.

- Username: `monitor`
- Password: stored in 1Password (search "OpsPocket Uptime Kuma edge auth"). The bcrypt hash is in `infra/caddy-sites/monitoring.caddy`.

To rotate:

```bash
NEW_PW='...'
ssh dev "caddy hash-password --plaintext '$NEW_PW'"
# paste hash into infra/caddy-sites/monitoring.caddy → basic_auth block
ssh dev 'sudo cp /path/to/monitoring.caddy /etc/caddy/Caddyfile.d/monitoring.caddy && sudo systemctl reload caddy'
```

## Deploy recipe

```bash
# 1. Data dir
ssh dev 'sudo mkdir -p /var/lib/opspocket/uptime-kuma-data'

# 2. Container
ssh dev 'docker run -d \
  --name uptime-kuma \
  --restart unless-stopped \
  -p 127.0.0.1:3001:3001 \
  -v /var/lib/opspocket/uptime-kuma-data:/app/data \
  louislam/uptime-kuma:1'

# 3. Caddy
scp infra/caddy-sites/monitoring.caddy dev:/tmp/
ssh dev 'sudo mv /tmp/monitoring.caddy /etc/caddy/Caddyfile.d/monitoring.caddy \
  && sudo systemctl reload caddy'

# 4. DNS (status.opspocket.com → 178.104.242.211, proxied)
#    Already created; see Cloudflare record id 96d86b9048a7ea9800bcd888da4e9808.
```

## First-run admin setup

1. Visit https://status.opspocket.com/ — provide edge basic auth (`monitor` / generated pw).
2. Uptime Kuma will prompt to create its own admin account. Store that in 1Password separately.
3. Add the 7 production monitors (below).

## Monitors to create

All are `HTTP(s)` type, 60s interval, 20s timeout, 2 retries.

| Name | URL | Method | Expected status | Notes |
|---|---|---|---|---|
| opspocket.com | https://opspocket.com/ | GET | 200 | Public marketing site |
| darleyabbeyfc.com | https://darleyabbeyfc.com/ | GET | 200 | Club site |
| dafc forms-api | https://forms.darleyabbeyfc.com/ | GET | 404 | POST-only endpoint — 404 is healthy. Use "Accepted Status Codes = 404". |
| aressentinel forms-api /health | https://forms.aressentinel.com/health | GET | 200 | Forms API health probe |
| glowpower.co.uk | https://glowpower.co.uk/ | GET | 200 | |
| magichairstyler.com | https://magichairstyler.com/ | GET | 200 | |
| vantabiolabs.xyz | https://vantabiolabs.xyz/ | GET | 200 | |

Optional niceties once monitors exist:

- Create a public **Status Page** in Uptime Kuma ("Status Pages" → "Add") that aggregates all 7, if you want a public-facing board. (Leave it unpublished or behind Cloudflare Access if you want to keep it private.)
- Add a notification integration (Slack, Discord, email) under **Settings → Notifications** and attach to each monitor.

## API / automation

Uptime Kuma v1 does **not** ship a first-class REST API; the web UI speaks Socket.IO. Community wrappers exist (e.g. `uptime-kuma-api` Python lib) but for 7 monitors we just document the manual setup above. When/if we upgrade to v2 with REST we can script this.

## Validation

```bash
ssh dev 'docker ps --filter name=uptime-kuma'
curl -I https://status.opspocket.com/
# expect HTTP/2 401 (Caddy basic-auth) until credentials supplied
curl -I -u 'monitor:<password>' https://status.opspocket.com/
# expect HTTP/2 302 or 200 (Uptime Kuma setup/login)
```
