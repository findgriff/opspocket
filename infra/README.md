# infra/ — provisioning artefacts

Everything needed to turn a blank Ubuntu 22.04/24.04 VPS into a running OpenClaw
tenant with MCP behind auto-TLS, ready for the OpsPocket mobile app.

## Files

| File | Purpose |
|------|---------|
| `install-openclaw.sh` | The actual installer. Run as root on a fresh box. Idempotent. |
| `cloud-init.yaml` | Tenant bootstrap template the orchestrator fills in at signup time. |
| `provision-tenant.sh` | Creates a customer VPS on Hetzner + writes `tenants.json`. |
| `destroy-tenant.sh` | Tears down a tenant VPS + removes it from `tenants.json`. |
| `test-installer.sh` | Dev-box Docker smoke-test for the installer. |

## Destroying a tenant

```bash
# By tenant id (preferred — from tenants.json or the provisioning summary):
./infra/destroy-tenant.sh --tenant-id a1b2c3d4

# By customer email (looked up in tenants.json first, then Hetzner labels):
./infra/destroy-tenant.sh --email customer@example.com

# By raw Hetzner server id (last resort):
./infra/destroy-tenant.sh --server-id 12345678

# Non-interactive (for the future orchestrator):
./infra/destroy-tenant.sh --tenant-id a1b2c3d4 --yes
```

The script:
- requires `HETZNER_TOKEN` env var (or a saved token at `~/.opspocket/hetzner-token`),
- prints what it's about to delete and prompts for `type 'destroy' to confirm`
  (skip with `--yes`),
- calls `DELETE /v1/servers/{id}` on the Hetzner API,
- removes the matching record from `infra/tenants.json` (`jq` in place),
- cleans up the local `~/.ssh/known_hosts` entry for the deleted IP.

**DNS cleanup is manual.** Each customer's domain may live in a different
DNS zone, so `destroy-tenant.sh` prints a `TODO (manual): remove DNS record for
<domain>` at the end rather than guessing. Remove the A record yourself.

## CI — `installer-ci.yml`

GitHub Actions runs `install-openclaw.sh` inside an Ubuntu 24.04 Docker container
on every PR and push to `main` that touches `infra/**`. The workflow is at
`.github/workflows/installer-ci.yml` and uses the same verification pattern as
`test-installer.sh`. Because CI has no reachable Ollama endpoint, the job runs
with `MODEL_PROVIDER=ollama` + `SKIP_MODEL_HEALTHCHECK=1` so the installer
skips the model-provider reachability probe but still exercises every other
code path.

## Development loop

**Testing the installer against a throwaway box (before we hook up billing):**

```bash
# Spin up the cheapest Vultr/Hetzner droplet (Ubuntu 24.04).
# ssh in as root, then:

curl -fsSL https://raw.githubusercontent.com/<your-gh>/opspocket/main/infra/install-openclaw.sh \
  -o install.sh && chmod +x install.sh

# Dev run — IP-only, no TLS, no OpenAI key yet
sudo bash install.sh

# Prod-shaped run — real domain, TLS, API key baked in
sudo DOMAIN=test-01.opspocket.cloud \
     ADMIN_EMAIL=ops@opspocket.cloud \
     OPENAI_API_KEY=sk-proj-... \
     bash install.sh
```

The installer prints the MCP token + connection details at the end. Use those
to configure a server in the OpsPocket mobile app.

## What gets installed

1. **Node.js 20 LTS** (via NodeSource apt repo).
2. **`clawd`** system user with a workspace at `/home/clawd/clawd`.
3. **`openclaw`** CLI globally via npm (name TBC — see note in script).
4. **`openclaw-gateway.service`** — systemd unit that runs `openclaw gateway`
   and exposes the MCP endpoint on `127.0.0.1:3000`.
5. **Caddy** — reverse-proxy on 80/443. Terminates TLS via Let's Encrypt when
   `DOMAIN` is set. Gates `/mission-control/api/mcp` behind a Bearer token.
6. **UFW** — only SSH + 80 + 443 open.
7. **`/home/clawd/.openclaw/.env`** — secrets file, chmod 600.

## What's deliberately NOT installed (yet)

- Supabase logging (opt-in; customer toggles later)
- Telegram integration (per-tenant, configured post-signup)
- Daily backup cron (added in v1.1 with Vultr/Hetzner snapshot API)
- Monitoring/alerting (Uptime Kuma or similar, ops-side)

## Security model (v1)

- **MCP endpoint** is gated by `Authorization: Bearer <MCP_TOKEN>`. The token
  is generated per-install, not shared between tenants.
- **SSH** is disabled for customers — only `ops` has a key. Customer-facing
  auth is MCP-only.
- **Firewall** denies everything inbound except 22/80/443.
- **OpenAI keys** sit in a 600-permission env file owned by `clawd`. Not in
  the openclaw.json config (where our stale install had them).

Known gaps we'll close in v1.1:
- No fail2ban yet
- No automatic security patches (`unattended-upgrades`)
- No rate-limit on MCP (Caddy supports it via plugin — 5-min add)

## Known uncertainties (things to verify against a real install)

- **`openclaw` npm package name.** The installer tries `npm install -g openclaw`,
  falling back to git. We need to confirm the canonical package ID from the
  official project and pin to a version.
- **Gateway port.** Defaults to 3000; configurable via `GATEWAY_PORT` env.
  Verify against `ss -ltnp` after install.
- **MCP path.** We're serving at `/mission-control/api/mcp` to match the
  existing OpenClaw UI convention. If the canonical gateway binds a different
  path, update the Caddyfile handle blocks.
- **Mission-control Next.js UI.** Currently assumed to be served by the same
  gateway process. If it's a separate service, add a second systemd unit.

The script is written to fail loud on any of these rather than silently
produce a broken install. Re-running after a fix is safe.
