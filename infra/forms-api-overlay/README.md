# forms-api overlay image

Thin Docker overlay over `dokku/forms-api:latest` that rewrites the baked
env file so runtime env vars (DB host, SMTP creds, etc.) reflect the
migrated-to-Hetzner setup instead of the old DigitalOcean Dokku config.

## Why this exists

The base image (inherited from Dokku's herokuish buildpack) bakes the
deployment-time env into `/app/.profile.d/01-app-env.sh`. Herokuish sources
that file AFTER Docker env vars are injected, so values from
`docker run --env-file …` get clobbered on the way in. Specifically, the
original `DATABASE_URL` pointed at a DO-private MariaDB hostname that
doesn't exist on our new Hetzner box. Without this overlay, the app
runs but can't connect to its DB.

## Build

```
# One-time: copy the example to your real env file (gitignored)
cp .env.example .env
vim .env              # fill in DATABASE_URL pw, SMTP creds, FORM_API_KEY

./build.sh            # renders Dockerfile.template → Dockerfile → image 'forms-api:local'
```

## Deploy on the dev box

```
docker rm -f forms-api 2>/dev/null || true
docker run -d \
  --name forms-api \
  --restart=always \
  --network forms-net \
  -p 127.0.0.1:5103:5000 \
  forms-api:local \
  /start web
```

## Files

| File | Committed? | Purpose |
|---|---|---|
| `Dockerfile.template` | ✅ | placeholder-substitution template |
| `.env.example` | ✅ | shape + docs |
| `build.sh` | ✅ | substitute → build |
| `README.md` | ✅ | this file |
| `.env` | ❌ gitignored | real values |
| `Dockerfile` | ❌ gitignored | rendered with real values |

## Rotating a secret

E.g., if the MariaDB root password is rotated (see `/root/forms-db-root.txt`
on the dev box):

1. Update `.env` with the new password
2. `./build.sh`
3. `docker rm -f forms-api && docker run -d ... forms-api:local /start web`

Takes < 30 seconds, zero downtime for the DB itself.
