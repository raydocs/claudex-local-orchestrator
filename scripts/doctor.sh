#!/usr/bin/env bash
set -euo pipefail
REQUIRE_MODELS=0
[[ "${1:-}" == --require-models ]] && REQUIRE_MODELS=1
CONFIG="${CLAUDEX_LOCAL_CONFIG_HOME:-$HOME/.config/claudex-local}"
MODELS="$CONFIG/models.json"
errors=0
check(){ if "$@" >/dev/null 2>&1; then printf 'PASS  %s\n' "$*"; else printf 'FAIL  %s\n' "$*"; errors=$((errors+1)); fi; }
for c in claude cli-proxy-api node python3; do check command -v "$c"; done
if command -v claude >/dev/null 2>&1; then printf 'NOTE  oracle side-channel available via native claude CLI\n'; fi
for f in "$CONFIG/settings.json" "$CONFIG/orchestrator.md" "$MODELS" "$HOME/.local/bin/claudex-local" "$HOME/.local/share/claudex-local/model-filter-proxy.mjs"; do [[ -f "$f" ]] && printf 'PASS  %s\n' "$f" || { printf 'FAIL  %s\n' "$f"; errors=$((errors+1)); }; done
# Check the gateway config the running service actually uses; fall back to the
# rendered default location for brew installs that are not running yet.
LIVE_CONF="$(ps -axo command | sed -n 's/.*cli-proxy-api .*-config \([^ ]*\).*/\1/p' | head -n1)"
[[ -n "$LIVE_CONF" && -f "$LIVE_CONF" ]] || LIVE_CONF="$HOME/.cli-proxy-api/config.yaml"
printf 'NOTE  gateway config in effect: %s\n' "$LIVE_CONF"
if [[ -f "$LIVE_CONF" ]] && grep -q 'api-key:[[:space:]]*"unset-kimi-key"' "$LIVE_CONF"; then
  printf 'FAIL  Kimi key is still unset in %s\n' "$LIVE_CONF"
  errors=$((errors+1))
fi
check nc -z 127.0.0.1 8317
check nc -z 127.0.0.1 8318
if [[ -f "$CONFIG/settings.json" && -f "$MODELS" ]] && nc -z 127.0.0.1 8318 2>/dev/null; then
  if python3 - "$CONFIG/settings.json" "$MODELS" <<'PY2'
import json,sys,urllib.request
s=json.load(open(sys.argv[1])); token=s['env']['ANTHROPIC_AUTH_TOKEN']
models=json.load(open(sys.argv[2]))
r=urllib.request.Request('http://127.0.0.1:8318/v1/models',headers={'Authorization':f'Bearer {token}'})
with urllib.request.urlopen(r,timeout=10) as response: payload=json.load(response)
seen={x.get('id') for x in payload.get('data',[]) if isinstance(x,dict)}
required={role['model'] for role in models['roles'].values() if role['required_in_catalog'] and role['channel']=='gateway'}
missing=sorted(required-seen)
print('MODELS '+('PASS' if not missing else 'MISSING '+','.join(missing)))
raise SystemExit(bool(missing))
PY2
  then :; elif ((REQUIRE_MODELS)); then errors=$((errors+1)); else printf 'WARN  exact model catalog incomplete; authenticate providers before live use\n'; fi
fi
((errors==0)) || exit 1
