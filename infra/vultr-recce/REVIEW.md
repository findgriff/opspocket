# Review: openclaw-generated-installer.sh

OpenClaw 2026.4.5 (running on the Vultr Marketplace box) produced this
installer when asked to replicate its own setup on a generic Ubuntu 24.04
box. It's ~90% correct and reflects the authoritative install recipe —
but has a handful of bugs we need to fix before it'll run clean on
Hetzner. Captured verbatim for traceability.

## What it gets right

- ✅ Correct Node 22 + Caddy + Docker + code-server install via official apt repos
- ✅ Correct `openclaw@2026.4.5` + `clawhub@0.9.0` version pinning from live `npm ls -g`
- ✅ Full `openclaw-gateway.service` user-unit reproduced verbatim from the running system
- ✅ `loginctl enable-linger` called so the user service survives logout
- ✅ Idempotent with `if ! command -v …` guards
- ✅ Flags Vultr-specific parts clearly (ZeroSSL EAB, `*.vultropenclaw.com`)

## Bugs to fix before running

Priority ordered — top ones would cause the script to silently produce
a broken install.

### 1. `basic_auth` password hash is wrong **[CRITICAL]**

```bash
basic_auth { clawmine $(caddy hash-password --plaintext 'CHANGE_ME') }
```

Two problems:
- `$(…)` inside an un-quoted heredoc gets evaluated AT SCRIPT-WRITE TIME,
  before we have a real password. The literal string "CHANGE_ME" ends up
  hardcoded into the Caddyfile.
- `caddy hash-password --plaintext` flag may not be correct syntax in
  newer Caddy versions; it expects stdin.

Fix: pre-compute the hash to a variable before writing the Caddyfile:

```bash
HASH=$(echo -n "${ADMIN_PASSWORD}" | caddy hash-password)
# then in the heredoc:
basic_auth { clawmine $HASH }
```

### 2. `${...}` placeholders in openclaw.json won't expand **[CRITICAL]**

The heredoc for `openclaw.json` uses `\${DOMAIN}`, `\${OPENAI_API_KEY}`
etc — these are escaped, so they land in the file as *literal strings*,
not substituted values. OpenClaw won't magically expand them at runtime
(we didn't find any evidence of env-var expansion in its config loader).

Fix: use un-escaped `${...}` so bash expands them during the cat, OR
generate the JSON with `jq` / `envsubst` for safety with special chars:

```bash
envsubst < openclaw.json.tpl > /home/$ADMIN_USER/.openclaw/openclaw.json
```

Also — `${OPENAI_API_KEY}` inside the bash heredoc would try to expand
the shell var of the same name, which IS set (the script requires it at
the top). But the escaping breaks it. Remove the backslash.

### 3. `${DOMAIN}` inside the Caddyfile heredoc — same issue

Same bug as above — `\${DOMAIN}` is written literally to `/etc/caddy/Caddyfile`,
making Caddy try to serve for a literal hostname `${DOMAIN}`. Fix with
unescaped `$DOMAIN`.

### 4. Verification will always say "Caddy HTTPS not ready"

```bash
if curl -sf https://${DOMAIN}/ >/dev/null 2>&1; then
```

The `-f` flag fails on any 4xx, and `/` will return **401 Unauthorized**
because of the `basic_auth` block. So even a perfectly working install
will report "not ready". Fix: check for `401` as success (it proves
Caddy + auth are both live):

```bash
STATUS=$(curl -sS -o /dev/null -w "%{http_code}" --max-time 10 "https://${DOMAIN}/" || echo 000)
[[ "$STATUS" == "401" || "$STATUS" == "200" ]] && echo "✅ Caddy + auth responding"
```

### 5. User-level systemctl needs the runtime dir to exist

```bash
sudo -u "$ADMIN_USER" XDG_RUNTIME_DIR="/run/user/$(id -u "$ADMIN_USER")" \
  systemctl --user daemon-reload
```

`/run/user/$UID` is only created when the user logs in or linger is
established. `loginctl enable-linger` (called earlier) does create it,
but there's a race — linger takes a second or two to kick in. A short
sleep or explicit `machinectl shell` is safer:

```bash
loginctl enable-linger "$ADMIN_USER"
# Wait for /run/user/$UID to exist
for i in {1..10}; do
  [[ -d "/run/user/$(id -u "$ADMIN_USER")" ]] && break
  sleep 1
done
```

### 6. Missing `${PORT:-3000}` fallback pattern

The reference env block sets `OPENCLAW_GATEWAY_PORT=18789` both in the
systemd unit AND in openclaw.json `gateway.port`. If one is changed and
the other isn't, weird debugging. Prefer to read one from the other, or
document that they must match.

### 7. `bind: "lan"` is a security gotcha

The Vultr Marketplace box had `"bind": "lan"` which means the gateway
listens on `0.0.0.0:18789` — directly reachable from the internet,
bypassing Caddy's basic auth. We should change this to `"loopback"`
so only Caddy (on 127.0.0.1) can reach it:

```json
"gateway": {
  "port": 18789,
  "bind": "loopback",   // was "lan" — production hardening
  ...
}
```

### 8. `OPENAI_API_KEY` parameter but config uses it generically

The script requires `OPENAI_API_KEY` as input, but the `openclaw.json`
template calls the provider `"my-provider"` using a placeholder. For
clarity, either:
- Rename the provider key to `"openai"` so it matches the conventional name
- OR accept a generic `MODEL_API_KEY` and `MODEL_PROVIDER_NAME` input

## Plan for tomorrow

1. Fix the bugs above into a cleaned `install-openclaw.sh` in the repo
   root (replacing my earlier draft at `infra/install-openclaw.sh`)
2. Run the cleaned script on a fresh Hetzner CPX22
3. Smoke-test: gateway responds, MCP endpoint reachable, Caddy auth works
4. If everything passes, this is our portable installer — works on any
   Ubuntu 24.04 host, no Marketplace dependency

Target: ~45 min of work to polish + test tomorrow, once we have a
fresh Hetzner box to run against.
