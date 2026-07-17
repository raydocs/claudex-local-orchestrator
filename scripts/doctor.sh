#!/usr/bin/env bash
set -euo pipefail
REQUIRE_MODELS=0
[[ "${1:-}" == --require-models ]] && REQUIRE_MODELS=1
CONFIG="${CLAUDEX_LOCAL_CONFIG_HOME:-$HOME/.config/claudex-local}"
errors=0
check(){ if "$@" >/dev/null 2>&1; then printf 'PASS  %s\n' "$*"; else printf 'FAIL  %s\n' "$*"; errors=$((errors+1)); fi; }
for c in claude cli-proxy-api node python3; do check command -v "$c"; done
for f in "$CONFIG/settings.json" "$CONFIG/orchestrator.md" "$HOME/.local/bin/claudex-local" "$HOME/.local/share/claudex-local/model-filter-proxy.mjs"; do [[ -f "$f" ]] && printf 'PASS  %s\n' "$f" || { printf 'FAIL  %s\n' "$f"; errors=$((errors+1)); }; done
check nc -z 127.0.0.1 8317
check nc -z 127.0.0.1 8318
if [[ -f "$CONFIG/settings.json" ]] && nc -z 127.0.0.1 8318 2>/dev/null; then
  if python3 - "$CONFIG/settings.json" <<'PY2'
import json,sys,urllib.request
s=json.load(open(sys.argv[1])); token=s['env']['ANTHROPIC_AUTH_TOKEN']
r=urllib.request.Request('http://127.0.0.1:8318/v1/models',headers={'Authorization':f'Bearer {token}'})
with urllib.request.urlopen(r,timeout=10) as response: payload=json.load(response)
seen={x.get('id') for x in payload.get('data',[]) if isinstance(x,dict)}
required={'gpt-5.6-sol','gpt-5.6-luna','gpt-5.6-terra','grok-4.5','gemini-3.5-flash','glm-5.2'}
missing=sorted(required-seen)
print('MODELS '+('PASS' if not missing else 'MISSING '+','.join(missing)))
raise SystemExit(bool(missing))
PY2
  then :; elif ((REQUIRE_MODELS)); then errors=$((errors+1)); else printf 'WARN  exact model catalog incomplete; authenticate providers before live use\n'; fi
fi
((errors==0)) || exit 1
