# Caddy per-site configs (Caddyfile.d)

These files get rendered into `/etc/caddy/Caddyfile.d/*.caddy` on the
OpsPocket dev box (`opspocket-dev`, Hetzner CX43, Nuremberg, IP
`178.104.242.211`). The main `/etc/caddy/Caddyfile` is just:

```
{
    email findgriff@gmail.com
}

import Caddyfile.d/*.caddy
```

So per-site configs can be added or changed independently. Every TLS
block uses the Cloudflare DNS-01 challenge via `{env.CLOUDFLARE_API_TOKEN}`,
which is loaded by systemd from `/etc/caddy/cloudflare.env`.

## Sites served from this box (as of 2026-04-22)

| File | Hostnames | Backend | Notes |
|---|---|---|---|
| `opspocket.caddy` | opspocket.com, www.opspocket.com | static + `/api/waitlist` → 127.0.0.1:8091 | Public marketing site |
| `dev.caddy` | hello.dev.opspocket.com, *.dev.opspocket.com | respond | Dev-box health + test-tenant catch-all |
| `dafc.caddy` | darleyabbeyfc.com, www. | static `/var/www/darleyabbeyfc.com` | Darley Abbey FC |
| `dafc-forms.caddy` | forms.darleyabbeyfc.com | 127.0.0.1:5102 | DAFC forms handler (SMTP) |
| `forms-api.caddy` | forms.aressentinel.com | 127.0.0.1:5103 | Forms API + MariaDB |
| `glowpower.caddy` | glowpower.co.uk, www. | 127.0.0.1:5100 | Glow Power site |
| `magichairstyler.caddy` | magichairstyler.com, www. | static `/var/www/magichairstyler.com` | Magic Hair Styler |
| `vantabiolabs.caddy` | vantabiolabs.xyz, www. | 127.0.0.1:5101 | Vanta Bio Labs (Next.js) |

## Reverse-proxy port assignments

| Port | Container | Purpose |
|---|---|---|
| 3306 | `forms-db-mariadb` | MariaDB for forms-api (loopback only) |
| 5100 | `glowpower` | |
| 5101 | `vantabiolabs` | |
| 5102 | `dafc-forms` | |
| 5103 | `forms-api` | |
| 8091 | `opspocket-waitlist` (Python svc) | /api/waitlist on opspocket.com |
| 11434 | `ollama` (host) | Local LLM for testing |
| 18789 | `openclaw-gateway` (planned) | OpenClaw gateway on dev box (not yet set up) |

## Adding a new site

1. Write a new `<app>.caddy` file here
2. `scp` it to `dev:/etc/caddy/Caddyfile.d/<app>.caddy`
3. `ssh dev 'systemctl reload caddy'` (not restart — reload is enough for config changes)
4. Caddy auto-obtains TLS cert via Cloudflare DNS-01 on first request

## Modifying the CF token

If the token in `/etc/caddy/cloudflare.env` changes you MUST
`systemctl restart caddy` — `reload` doesn't re-read `EnvironmentFile`.
