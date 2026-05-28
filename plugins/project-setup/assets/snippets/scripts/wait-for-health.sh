#!/usr/bin/env bash
# Wait for given compose services to report healthy.
# Usage: ./scripts/wait-for-health.sh postgres redis [timeout-seconds]

set -euo pipefail

services=("$@")
timeout=60

# If the last arg looks like a number, treat it as the timeout.
if [[ "${services[-1]}" =~ ^[0-9]+$ ]]; then
  timeout="${services[-1]}"
  unset 'services[-1]'
fi

proj="${COMPOSE_PROJECT_NAME:-$(basename "$PWD")}"
elapsed=0
while (( elapsed < timeout )); do
  all_healthy=true
  for svc in "${services[@]}"; do
    status=$(docker inspect -f '{{.State.Health.Status}}' "${proj}-${svc}" 2>/dev/null || echo "unknown")
    if [[ "$status" != "healthy" ]]; then all_healthy=false; break; fi
  done
  $all_healthy && { echo "✓ all healthy: ${services[*]}"; exit 0; }
  sleep 2
  elapsed=$((elapsed + 2))
done

echo "✗ services did not become healthy within ${timeout}s: ${services[*]}" >&2
echo "  Try: docker compose -f docker/compose.yaml logs ${services[*]}" >&2
exit 1
