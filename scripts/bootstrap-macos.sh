#!/usr/bin/env bash
set -euo pipefail
MODE=check
REPLACE=0
while (($#)); do
  case "$1" in
    --check) MODE=check ;;
    --install) MODE=install ;;
    --replace-existing) REPLACE=1 ;;
    -h|--help) printf 'Usage: %s --check | --install [--replace-existing]\n' "$0"; exit 0 ;;
    *) printf 'unknown argument: %s\n' "$1" >&2; exit 2 ;;
  esac
  shift
done
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)"
CONFIG="$HOME/.config/claudex-local"
SHARE="$HOME/.local/share/claudex-local"
BIN="$HOME/.local/bin"
PLIST="$HOME/Library/LaunchAgents/local.claudex-local.model-filter.plist"
CLIPROXY="$HOME/.cli-proxy-api/config.yaml"
BREW_CONFIG=""
STAMP="$(date +%Y%m%d%H%M%S)"
fail(){ printf 'bootstrap: %s\n' "$*" >&2; exit 1; }
[[ "$(uname -s)" == Darwin ]] || fail 'macOS is required'
for cmd in brew node python3 claude cli-proxy-api openssl curl nc launchctl; do command -v "$cmd" >/dev/null || fail "missing $cmd"; done
BREW_CONFIG="$(brew --prefix)/etc/cliproxyapi.conf"
for path in config/models.json config/examples/settings.json.template config/examples/cliproxyapi.yaml.template config/examples/local.claudex-local.model-filter.plist.template config/orchestrator.md scripts/claudex-local scripts/claudex-usage scripts/oracle-consult adapter/model-filter-proxy.mjs agents; do [[ -e "$ROOT/$path" ]] || fail "missing $path"; done
printf 'bootstrap: prerequisites PASS\n'
printf 'bootstrap: adapter 127.0.0.1:8318 -> CLIProxyAPI 127.0.0.1:8317\n'
[[ "$MODE" == install ]] || exit 0
backup(){ local p="$1"; if [[ -e "$p" || -L "$p" ]]; then ((REPLACE)) || fail "$p exists; inspect it and rerun with --replace-existing"; cp -pPR "$p" "$p.backup.$STAMP"; fi; }
for p in "$CONFIG/settings.json" "$CONFIG/orchestrator.md" "$CONFIG/models.json" "$CONFIG/claude/agents" "$SHARE/model-filter-proxy.mjs" "$BIN/claudex-local" "$BIN/claudex-usage" "$BIN/oracle-consult" "$PLIST" "$CLIPROXY" "$BREW_CONFIG"; do backup "$p"; done
mkdir -p "$CONFIG/claude" "$SHARE" "$BIN" "$HOME/.cli-proxy-api" "$HOME/Library/LaunchAgents"
chmod 0700 "$CONFIG" "$CONFIG/claude" "$HOME/.cli-proxy-api"
LOCAL_KEY="$(openssl rand -hex 32)"
RENDER_KIMI_API_KEY=""
if [[ -n "${KIMI_API_KEY:-}" ]]; then
  RENDER_KIMI_API_KEY="$KIMI_API_KEY"
elif [[ -t 0 ]]; then
  printf 'bootstrap: Moonshot KIMI_API_KEY (hidden; empty skips): ' >&2
  IFS= read -r -s RENDER_KIMI_API_KEY || true
  printf '\n' >&2
fi
if [[ -z "$RENDER_KIMI_API_KEY" ]]; then
  RENDER_KIMI_API_KEY="unset-kimi-key"
  printf 'bootstrap: WARN Kimi key not provided; kimi-k3 will fail doctor until config.yaml is updated manually\n' >&2
fi
export RENDER_HOME="$HOME" RENDER_KEY="$LOCAL_KEY" RENDER_NODE="$(command -v node)" RENDER_ADAPTER="$SHARE/model-filter-proxy.mjs" RENDER_KIMI_API_KEY
python3 - "$ROOT" "$CONFIG" "$CLIPROXY" "$PLIST" <<'PY2'
import os, pathlib, sys
root, config, cliproxy, plist = map(pathlib.Path, sys.argv[1:])
models = __import__('json').loads((root/'config/models.json').read_text())
m = {'__HOME__':os.environ['RENDER_HOME'],'__LOCAL_API_KEY__':os.environ['RENDER_KEY'],'__KIMI_API_KEY__':os.environ['RENDER_KIMI_API_KEY'],'__NODE_BINARY__':os.environ['RENDER_NODE'],'__ADAPTER_PATH__':os.environ['RENDER_ADAPTER'],'__DEFAULT_SUBAGENT_MODEL__':models['default_subagent_model'],'__COMPACTION_MODEL__':models['roles']['compaction']['model']}
def render(src,dst):
 t=src.read_text()
 for a,b in m.items(): t=t.replace(a,b)
 if '__' in t: raise SystemExit(f'unresolved placeholder in {src}')
 dst.parent.mkdir(parents=True,exist_ok=True); dst.write_text(t); dst.chmod(0o600)
render(root/'config/examples/settings.json.template',config/'settings.json')
render(root/'config/examples/cliproxyapi.yaml.template',cliproxy)
render(root/'config/examples/local.claudex-local.model-filter.plist.template',plist)
PY2
cp "$ROOT/config/orchestrator.md" "$CONFIG/orchestrator.md"
cp "$ROOT/config/models.json" "$CONFIG/models.json"
rm -rf "$CONFIG/claude/agents"
cp -R "$ROOT/agents" "$CONFIG/claude/agents"
cp "$ROOT/adapter/model-filter-proxy.mjs" "$SHARE/model-filter-proxy.mjs"
cp "$ROOT/scripts/claudex-local" "$BIN/claudex-local"
cp "$ROOT/scripts/claudex-usage" "$BIN/claudex-usage"
cp "$ROOT/scripts/oracle-consult" "$BIN/oracle-consult"
chmod 0600 "$CONFIG/settings.json" "$CONFIG/orchestrator.md" "$CONFIG/models.json" "$CLIPROXY" "$PLIST"
chmod 0644 "$SHARE/model-filter-proxy.mjs" "$CONFIG/claude/agents"/*.md
chmod 0755 "$BIN/claudex-local" "$BIN/claudex-usage" "$BIN/oracle-consult"
if brew list cliproxyapi >/dev/null 2>&1; then
  mkdir -p "$(dirname "$BREW_CONFIG")"
  ln -sfn "$CLIPROXY" "$BREW_CONFIG"
  brew services restart cliproxyapi
else
  # Non-Homebrew CLIProxyAPI (e.g. a manually installed LaunchAgent): its live
  # config is not ours to overwrite. Detect it and hand over honestly.
  LIVE_CONF="$(ps -axo command | sed -n 's/.*cli-proxy-api .*-config \([^ ]*\).*/\1/p' | head -n1)"
  printf 'bootstrap: WARN cliproxyapi is not a Homebrew service; skipped config symlink and restart\n' >&2
  printf 'bootstrap: WARN merge the provider blocks and the new local api-key from %s into %s, then restart that gateway service yourself\n' "$CLIPROXY" "${LIVE_CONF:-your live gateway config}" >&2
fi
launchctl bootout "gui/$(id -u)" "$PLIST" >/dev/null 2>&1 || true
launchctl bootstrap "gui/$(id -u)" "$PLIST"
printf 'bootstrap: installed claudex-local; provider login is still human-owned\n'
printf 'bootstrap: optional alias after inspection: ln -s %s %s\n' "$BIN/claudex-local" "$BIN/claudex"
