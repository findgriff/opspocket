#!/usr/bin/env bash
# Build the forms-api overlay image by substituting values from .env
# into Dockerfile.template.
#
# Usage:
#   cp .env.example .env          # only once
#   # edit .env with real values (DO NOT COMMIT)
#   ./build.sh
#
# Produces:
#   - Dockerfile                 (gitignored; contains real values)
#   - image tagged  forms-api:local
#
# Runs on the dev box (or anywhere Docker + a copy of the .env exists).

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$HERE"

[[ -f .env ]] || { echo "Missing .env (cp .env.example .env and fill in)" >&2; exit 1; }
[[ -f Dockerfile.template ]] || { echo "Missing Dockerfile.template" >&2; exit 1; }

# Source env file into a safe associative array
declare -A VARS
while IFS='=' read -r key value; do
  [[ -z "$key" || "$key" =~ ^# ]] && continue
  # strip surrounding quotes
  value="${value%\"}"; value="${value#\"}"
  value="${value%\'}"; value="${value#\'}"
  VARS["$key"]="$value"
done < .env

# Substitute __KEY__ placeholders in the template.
cp Dockerfile.template Dockerfile
for key in "${!VARS[@]}"; do
  value="${VARS[$key]}"
  # Use a perl-based replace to safely handle special chars in values.
  export KEY="$key" VAL="$value"
  perl -i -pe 's/__\Q$ENV{KEY}\E__/$ENV{VAL}/g' Dockerfile
done

# Build the image.
docker build -t forms-api:local .

echo ""
echo "✓ Built forms-api:local"
echo "Use with: docker run -d --name forms-api --restart=always \\"
echo "          --network forms-net -p 127.0.0.1:5103:5000 forms-api:local /start web"
