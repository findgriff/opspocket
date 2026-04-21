# Vultr Marketplace OpenClaw — complete recce

Captured from Vultr Cloud Compute 2 vCPU / 4 GB / 80 GB, London, Ubuntu 24.04,
with the "OpenClaw" Marketplace app selected on deploy. Captured 2026-04-21.

## The install is pre-baked into the Vultr image

There's no cloud-init user-data script we can extract. The Marketplace image
has OpenClaw already installed at image-build time. To replicate this on a
non-Vultr box we install the same packages + drop in the same configs.

## Exact package set

Installed globally via system-wide npm (at `/usr/lib/node_modules/`):

| Package | Version | Binary |
|---|---|---|
| `openclaw` | **2026.4.5** | `/usr/bin/openclaw` |
| `clawhub` | 0.9.0 | — |
| `npm` | 10.9.7 | (pinned, not LTS default) |

Installed via apt:

| Package | Purpose |
|---|---|
| `caddy` | reverse proxy + auto-TLS |
| `code-server` | browser VSCode |
| `docker-ce` + Docker CLI | agent sandbox runtime |
| `nodejs` (20+ / 22.22.2 observed) | JavaScript runtime |
| `git`, `curl`, `ca-certificates` | standard |

Not used but installed by the Marketplace image:

- Homebrew on Linux at `/home/linuxbrew/.linuxbrew` (empty on fresh install — for user use)

## User / directory layout

```
/home/
├── openclaw/              ← owns the gateway + data
│   ├── .openclaw/         ← workspace + config (see below)
│   └── .config/systemd/user/openclaw-gateway.service  ← user-level unit
├── linuxuser/             ← Vultr default non-root sudo user
└── linuxbrew/             ← Homebrew prefix (shared)
```

## The gateway is a *user*-level systemd service

**This is the critical detail** that was non-obvious. The gateway doesn't run
as a system-level systemd unit. It runs under `systemd --user` as the
`openclaw` user, with `loginctl enable-linger` so it keeps running across
logouts.

Full unit file captured below — drop-in replicable:

```ini
# /home/openclaw/.config/systemd/user/openclaw-gateway.service
[Unit]
Description=OpenClaw Gateway (v2026.4.5)
After=network-online.target
Wants=network-online.target

[Service]
ExecStart=/usr/bin/node /usr/lib/node_modules/openclaw/dist/index.js gateway --port 18789
Restart=always
RestartSec=5
TimeoutStopSec=30
TimeoutStartSec=30
SuccessExitStatus=0 143
KillMode=control-group
Environment=HOME=/home/openclaw
Environment=TMPDIR=/tmp
Environment=PATH=/usr/bin:/home/openclaw/.local/bin:/home/openclaw/.npm-global/bin:/home/openclaw/bin:/home/openclaw/.volta/bin:/home/openclaw/.asdf/shims:/home/openclaw/.bun/bin:/home/openclaw/.nvm/current/bin:/home/openclaw/.fnm/current/bin:/home/openclaw/.local/share/pnpm:/usr/local/bin:/bin
Environment=OPENCLAW_GATEWAY_PORT=18789
Environment=OPENCLAW_SYSTEMD_UNIT=openclaw-gateway.service
Environment="OPENCLAW_WINDOWS_TASK_NAME=OpenClaw Gateway"
Environment=OPENCLAW_SERVICE_MARKER=openclaw
Environment=OPENCLAW_SERVICE_KIND=gateway
Environment=OPENCLAW_SERVICE_VERSION=2026.4.5

[Install]
WantedBy=default.target
```

To enable after install:

```bash
sudo -u openclaw systemctl --user enable openclaw-gateway.service
sudo loginctl enable-linger openclaw
sudo -u openclaw systemctl --user start openclaw-gateway.service
```

## Caddyfile — exact routing

```
<tenant-uuid>.vultropenclaw.com {
    tls {
      issuer acme { dir https://acme.zerossl.com/v2/DV90  eab <redacted> }
      issuer acme { dir https://acme-v02.api.letsencrypt.org/directory }
    }

    basic_auth { clawmine <bcrypt-hash-redacted> }

    handle /code/* {
        uri strip_prefix /code
        reverse_proxy 127.0.0.1:6969
    }

    handle {
        reverse_proxy 127.0.0.1:18789 {
            header_up -X-Real-IP
            header_up -X-Forwarded-For
            transport http { versions 1.1 }
        }
    }
}
```

For Hetzner (or any non-Vultr provider), we replace
`<tenant-uuid>.vultropenclaw.com` with `<tenant-uuid>.opspocket.cloud` (our
own wildcard DNS) and drop the ZeroSSL issuer — just Let's Encrypt.

## Ports — what listens where

| Port | Bind | Service | Public? |
|---|---|---|---|
| 22 | 0.0.0.0 | sshd | ✅ |
| 80 / 443 | 0.0.0.0 | caddy | ✅ |
| 18789 | 0.0.0.0 | openclaw-gateway (direct) | ✅ (should be loopback behind Caddy) |
| 18791 | 127.0.0.1 | openclaw-gateway (internal) | ❌ |
| 40131 | 127.0.0.1 | openclaw-gateway (internal) | ❌ |
| 6969 | 127.0.0.1 | code-server | ❌ |
| 2019 | 127.0.0.1 | Caddy admin API | ❌ |

**Security note**: Vultr's Marketplace leaves gateway port 18789 bound to
`0.0.0.0` — directly reachable from the public internet, bypassing Caddy's
basic auth. For our production setup we should bind it to `127.0.0.1` and
let Caddy be the only public surface.

## MCP endpoint

`GET /mcp` on the gateway (port 18789 direct, or `/` on Caddy if basic-auth'd).
The old `/mission-control/api/mcp` path from the stale DO install does NOT
apply here — this is a different, newer gateway architecture.

## OpenClaw config — Vultr-specific bits

`openclaw.json` ships with a `vultr` model provider pointing at
`api.vultrinference.com/v1` with GLM-5.1-FP8 + DeepSeek-V3.2-NVFP4 listed
as zero-cost models. This is Vultr-exclusive — won't work on Hetzner. For
Hetzner we'd swap this block for either:

- `openai` provider with customer's own OpenAI API key
- Or a different LLM endpoint (Anthropic, Together, etc.)

The rest of `openclaw.json` structure is generic.

## Replication recipe — Hetzner CPX22 / any Ubuntu 24.04

```bash
# 1. System prep
apt update && apt install -y curl git caddy docker.io code-server

# 2. Node 20 LTS
curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
apt install -y nodejs

# 3. openclaw user + workspace
useradd -m -s /bin/bash openclaw
install -d -o openclaw -g openclaw -m 700 /home/openclaw/.openclaw

# 4. Install openclaw + clawhub npm packages globally
npm install -g openclaw@2026.4.5 clawhub@0.9.0

# 5. Drop the gateway user-unit (see above)
install -d -o openclaw -g openclaw /home/openclaw/.config/systemd/user
# <write unit file>
loginctl enable-linger openclaw
sudo -u openclaw systemctl --user enable --now openclaw-gateway.service

# 6. Caddyfile with OUR domain (not vultropenclaw.com)
# <write Caddyfile>
systemctl reload caddy

# 7. Initial openclaw.json — customer's OpenAI key (not Vultr inference)
# <sudo -u openclaw openclaw gateway --dev OR hand-write json>
```

This is what `infra/install-openclaw.sh` should become — a straight port of
the Marketplace image's install recipe. The existing `install-openclaw.sh`
in the repo was written before we had this recce and makes wrong
assumptions; worth rewriting from this blueprint once we're ready to
deploy on Hetzner.
