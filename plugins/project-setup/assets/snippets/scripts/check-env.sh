#!/usr/bin/env bash
# Diff .env keys against .env.example. Fail on missing keys.
# (Production-grade: also detect REQUIRED markers + empty values — simplified here.)

set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."

[[ -f .env ]]         || { echo "✗ no .env (run: ctl setup)"; exit 1; }
[[ -f .env.example ]] || { echo "✗ no .env.example"; exit 1; }

declare -A actual
while IFS='=' read -r key _; do
  [[ -z "$key" || "$key" =~ ^# ]] && continue
  actual["$key"]=1
done < .env

missing=()
while IFS='=' read -r key _; do
  [[ -z "$key" || "$key" =~ ^# ]] && continue
  [[ -v actual[$key] ]] || missing+=("$key")
done < .env.example

(( ${#missing[@]} > 0 )) && { echo "✗ missing keys in .env: ${missing[*]}"; exit 1; }
echo "✓ .env matches .env.example schema"
