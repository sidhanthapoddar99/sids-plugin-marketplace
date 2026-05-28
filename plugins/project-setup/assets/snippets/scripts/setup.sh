#!/usr/bin/env bash
# ctl setup — interactive .env wizard. Creates .env from .env.example and fills generated secrets.

set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."

[[ -f .env.example ]] || { echo "✗ no .env.example to template from" >&2; exit 1; }
if [[ ! -f .env ]]; then cp .env.example .env; echo "✓ created .env from .env.example"; fi

# Auto-generate any blank secret (keys ending _PASSWORD / _SECRET / _KEY).
while IFS='=' read -r key val; do
  [[ -z "$key" || "$key" =~ ^# ]] && continue
  if [[ "$key" =~ (_PASSWORD|_SECRET|_KEY)$ && -z "$val" ]]; then
    sed -i "s|^${key}=.*|${key}=$(openssl rand -hex 32)|" .env
    echo "✓ generated ${key}"
  fi
done < .env

echo "▸ remaining blanks to fill by hand:"
grep -nE '=$' .env || echo "  (none)"
echo "Then run: ctl dev"
