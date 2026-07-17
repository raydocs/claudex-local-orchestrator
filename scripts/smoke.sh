#!/usr/bin/env bash
set -euo pipefail

LIVE=0
while (($#)); do
  case "$1" in
    --live) LIVE=1 ;;
    -h|--help) printf 'Usage: %s [--live]\n' "$0"; exit 0 ;;
    *) printf 'smoke: unknown argument: %s\n' "$1" >&2; exit 2 ;;
  esac
  shift
done

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)"
cd "$ROOT"
CONFIG="${CLAUDEX_LOCAL_CONFIG_HOME:-$HOME/.config/claudex-local}"
errors=0
check(){ local label="$1"; shift; if "$@"; then printf 'PASS  %s\n' "$label"; else printf 'FAIL  %s\n' "$label"; errors=$((errors+1)); fi; }

catalog_check(){
  python3 - "$CONFIG/settings.json" "$CONFIG/models.json" <<'PY2'
import json, sys, urllib.request
settings = json.load(open(sys.argv[1]))
models = json.load(open(sys.argv[2]))
token = settings['env']['ANTHROPIC_AUTH_TOKEN']
request = urllib.request.Request('http://127.0.0.1:8318/v1/models', headers={'Authorization': f'Bearer {token}'})
with urllib.request.urlopen(request, timeout=10) as response:
    payload = json.load(response)
seen = {item.get('id') for item in payload.get('data', []) if isinstance(item, dict)}
required = {role['model'] for role in models['roles'].values() if role['required_in_catalog'] and role['channel'] == 'gateway'}
missing = sorted(required - seen)
if missing:
    print('missing models: ' + ', '.join(missing), file=sys.stderr)
    raise SystemExit(1)
PY2
}

printf 'Free tier (no model tokens spent)\n'
check 'static verification' bash scripts/verify.sh
check 'adapter tests' node --test adapter/model-filter-proxy.test.mjs
check 'doctor with required models' ./scripts/doctor.sh --require-models
check 'gateway model catalog' catalog_check

if ((LIVE)); then
  printf '\nWARNING: --live spends a small number of tokens on subscription/quota models.\n'
  temp="$(mktemp -d)"
  trap 'rm -rf "$temp"' EXIT
  token="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["env"]["ANTHROPIC_AUTH_TOKEN"])' "$CONFIG/settings.json" 2>/dev/null)" || token=''

  compaction_canary(){
    local marker code
    [[ -n "$token" ]] || return 1
    marker="$(node -e "import('./adapter/model-filter-proxy.mjs').then(m => process.stdout.write(m.COMPACTION_MARKERS[0]))")" || return 1
    python3 - "$marker" >"$temp/compaction-request.json" <<'PY2'
import json, sys
json.dump({'model': 'gpt-5.6-sol', 'max_tokens': 1, 'messages': [{'role': 'user', 'content': sys.argv[1]}]}, sys.stdout)
PY2
    code="$(curl -sS -D "$temp/compaction-headers" -o "$temp/compaction-body" -w '%{http_code}' \
      -H "Authorization: Bearer $token" -H 'content-type: application/json' \
      --data-binary @"$temp/compaction-request.json" http://127.0.0.1:8318/v1/messages)" || return 1
    [[ "$code" =~ ^[0-9]{3}$ ]] || return 1
    grep -Eiq '^x-claudex-local-route:[[:space:]]*compaction[[:space:]]*$' "$temp/compaction-headers" || return 1
    grep -Eiq '^x-claudex-local-routed-model:[[:space:]]*gpt-5\.6-luna[[:space:]]*$' "$temp/compaction-headers"
  }

  kimi_canary(){
    local code
    [[ -n "$token" ]] || return 1
    printf '%s' '{"model":"kimi-k3","max_tokens":16,"messages":[{"role":"user","content":"Reply with exactly: KIMI-OK"}]}' >"$temp/kimi-request.json"
    code="$(curl -sS -o "$temp/kimi-body" -w '%{http_code}' \
      -H "Authorization: Bearer $token" -H 'content-type: application/json' \
      --data-binary @"$temp/kimi-request.json" http://127.0.0.1:8318/v1/messages)" || return 1
    [[ "$code" == 200 ]] || return 1
    python3 - "$temp/kimi-body" <<'PY2'
import json, sys
body = json.load(open(sys.argv[1]))
assert body.get('type') != 'error' and 'error' not in body
PY2
  }

  isolation_probe(){
    local probe output
    probe='Do not use tools. Reply with only a JSON object {"skills":[...],"agent_types":[...]}, listing every skill and custom agent type available in this session.'
    output="$("$HOME/.local/bin/claudex-local" -p "$probe")"
    python3 - "$output" <<'PY2'
import json, sys
text = sys.argv[1].strip()
if text.startswith('```'):
    text = text.split('\n', 1)[1].rsplit('```', 1)[0]
payload = json.loads(text)
required = {'grok-worker', 'kimi-frontend-worker', 'grok-researcher', 'gpt-repo-explorer', 'gemini-url-digester', 'glm-transcript-reader'}
assert payload.get('skills') == []
assert required <= set(payload.get('agent_types', []))
PY2
  }

  oracle_canary(){
    command -v claude >/dev/null
    scripts/oracle-consult 'Reply with verdict approve if you can read this.' | grep -q approve
  }

  subagent_model_canary(){
    local output
    output="$("$HOME/.local/bin/claudex-local" -p 'Launch the kimi-frontend-worker agent via the Agent tool with this exact task: "Do not use any tools. Reply only with the exact model id you are running as." Relay its reply verbatim, prefixed with RESOLVED:')"
    printf '%s' "$output" | grep -q 'RESOLVED:.*kimi-k3'
  }

  check 'compaction canary' compaction_canary
  check 'Kimi canary' kimi_canary
  check 'isolation probe' isolation_probe
  check 'Oracle canary' oracle_canary
  check 'subagent model resolution' subagent_model_canary
fi

((errors==0)) || exit 1
