#!/usr/bin/env bash
set -euo pipefail
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)"
cd "$ROOT"
bash -n scripts/claudex-local scripts/bootstrap-macos.sh scripts/doctor.sh scripts/verify.sh
python3 <<'PY2'
import json,pathlib,plistlib,re
r=pathlib.Path('.')
required=['README.md','LICENSE','config/orchestrator.md','config/examples/settings.json.template','config/examples/cliproxyapi.yaml.template','config/examples/local.claudex-local.model-filter.plist.template','adapter/model-filter-proxy.mjs','adapter/model-filter-proxy.test.mjs','scripts/claudex-local','scripts/bootstrap-macos.sh','scripts/doctor.sh']
for p in required: assert (r/p).is_file(),p
m={'__HOME__':'/Users/test','__LOCAL_API_KEY__':'local-test-key','__NODE_BINARY__':'/opt/homebrew/bin/node','__ADAPTER_PATH__':'/Users/test/.local/share/claudex-local/model-filter-proxy.mjs'}
def render(p):
 t=(r/p).read_text()
 for a,b in m.items():t=t.replace(a,b)
 assert not re.search(r'__[A-Z0-9_]+__',t),p
 return t
s=json.loads(render('config/examples/settings.json.template'))
assert s['env']['ANTHROPIC_BASE_URL']=='http://127.0.0.1:8318'
y=render('config/examples/cliproxyapi.yaml.template')
assert 'host: "127.0.0.1"' in y and 'port: 8317' in y
pl=plistlib.loads(render('config/examples/local.claudex-local.model-filter.plist.template').encode())
assert pl['Label']=='local.claudex-local.model-filter'
agents=list((r/'agents').glob('*.md')); assert len(agents)>=5
for a in agents:
 t=a.read_text(); assert t.startswith('---') and 'model:' in t and 'tools:' in t
alltext='\n'.join(p.read_text(errors='ignore') for p in r.rglob('*') if p.is_file() and '.git' not in p.parts and p.as_posix() != 'scripts/verify.sh')
for pattern in [r'\bsk-[A-Za-z0-9_-]{20,}\b',r'\bgh[opsu]_[A-Za-z0-9]{20,}\b',r'\beyJ[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{10,}']:
 assert not re.search(pattern,alltext)
for forbidden in ['internal/mcpserver','claudex-workflow.v1.7.9']:
 assert forbidden not in alltext,forbidden
print('static verification: PASS')
PY2
