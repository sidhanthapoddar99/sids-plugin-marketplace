#!/usr/bin/env bash
# [ADAPT] the host apps — name → port → command. The ONE source for --help, --dry-run, and the run.
# Emitted as strings so help/dry-run print EXACTLY what runs (ports resolve from .env once loaded).
app_names() { printf '%s\n' api engine landing app docs dashboard single; }   # single = example-single-web-app-vite, the one-frontend shape
frontends() { printf '%s\n' landing app docs dashboard; }      # the ones the dev proxy fronts
# port_of VAR — the value from .env. Under --help the env may be absent: print the key name instead of dying.
port_of()   { local v="$1"; if [[ -n "${!v:-}" ]]; then echo "${!v}"; elif [[ "${HELP_MODE:-0}" == 1 ]]; then echo "\$$v"; else die "$v is blank in .env"; fi; }
app_port()  { case "$1" in
  api)       port_of API_PORT ;;          engine)    port_of ENGINE_PORT ;;
  landing)   port_of WEB_LANDING_PORT ;;  app)       port_of WEB_APP_PORT ;;
  single)    port_of WEB_APP_PORT ;;
  docs)      port_of WEB_DOCS_PORT ;;     dashboard) port_of DASHBOARD_PORT ;;
  *)         die "unknown app '$1' — one of: $(app_names | join_sp)" ;; esac; }
app_cmd()   { case "$1" in
  api)       printf 'uv run --directory apps/example-api-python uvicorn app.main:app --reload --host %q --port %q' "${API_HOST:-localhost}" "$(app_port api)" ;;
  engine)    printf 'cargo watch -C apps/example-engine-rust -x run' ;;
  landing)   printf 'bun --cwd apps/example-multi-web-app/landing dev --port %q' "$(app_port landing)" ;;
  app)       printf 'bun --cwd apps/example-multi-web-app/app dev --port %q' "$(app_port app)" ;;
  single)    printf 'bun --cwd apps/example-single-web-app-vite dev --port %q' "$(app_port single)" ;;
  docs)      printf 'bun --cwd apps/example-multi-web-app/docs dev --port %q' "$(app_port docs)" ;;
  dashboard) printf 'bun --cwd apps/example-dashboard-nextjs dev --port %q' "$(app_port dashboard)" ;;
  *)         die "unknown app '$1'" ;; esac; }

app_tools() { case "$1" in
  api) printf '%s\n' uv ;;
  engine) printf '%s\n' cargo cargo-watch ;;
  *) printf '%s\n' bun ;;
esac; printf '%s\n' curl; }

app_ready_cmd() { case "$1" in
  api) printf 'curl --fail --silent --max-time 1 %q' "http://${API_HOST:-localhost}:$(app_port api)${API_PREFIX:-/api}/ready" ;;
  engine) printf 'curl --fail --silent --max-time 1 %q' "http://${ENGINE_HOST:-localhost}:$(app_port engine)${ENGINE_PREFIX:-/engine}/ready" ;;
  *) printf 'curl --fail --silent --max-time 1 %q' "http://localhost:$(app_port "$1")/" ;;
esac; }

app_ready_timeout() { printf '%s\n' 30; }
