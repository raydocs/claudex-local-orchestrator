#!/usr/bin/env bash
set -euo pipefail
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)"
cd "$ROOT"
bash -n scripts/claudex-local scripts/bootstrap-macos.sh scripts/doctor.sh scripts/verify.sh scripts/oracle-consult
python3 <<'PY2'
import json,pathlib,plistlib,re
r=pathlib.Path('.')
required=['README.md','LICENSE','config/models.json','config/orchestrator.md','config/examples/settings.json.template','config/examples/cliproxyapi.yaml.template','config/examples/local.claudex-local.model-filter.plist.template','adapter/model-filter-proxy.mjs','adapter/model-filter-proxy.test.mjs','scripts/claudex-local','scripts/bootstrap-macos.sh','scripts/doctor.sh','scripts/oracle-consult']
for p in required: assert (r/p).is_file(),p
catalog=json.loads((r/'config/models.json').read_text())
assert catalog.get('version') == 1
assert isinstance(catalog.get('default_subagent_model'),str) and catalog['default_subagent_model']
roles=catalog.get('roles'); assert isinstance(roles,dict) and roles
for role_name,role in roles.items():
 assert isinstance(role,dict),role_name
 assert isinstance(role.get('model'),str) and role['model'],role_name
 assert role.get('channel') in {'gateway','native'},role_name
 assert isinstance(role.get('required_in_catalog'),bool),role_name
 assert role.get('agent') is None or isinstance(role['agent'],str),role_name
 assert isinstance(role.get('metered'),bool),role_name
m={'__HOME__':'/Users/test','__LOCAL_API_KEY__':'local-test-key','__KIMI_API_KEY__':'kimi-test-key','__NODE_BINARY__':'/opt/homebrew/bin/node','__ADAPTER_PATH__':'/Users/test/.local/share/claudex-local/model-filter-proxy.mjs','__DEFAULT_SUBAGENT_MODEL__':catalog['default_subagent_model'],'__COMPACTION_MODEL__':roles['compaction']['model']}
def render(p):
 t=(r/p).read_text()
 for a,b in m.items():t=t.replace(a,b)
 assert not re.search(r'__[A-Z0-9_]+__',t),p
 return t
s=json.loads(render('config/examples/settings.json.template'))
assert s['env']['ANTHROPIC_BASE_URL']=='http://127.0.0.1:8318'
assert s['env']['CLAUDE_CODE_SUBAGENT_MODEL']==catalog['default_subagent_model']
y=render('config/examples/cliproxyapi.yaml.template')
assert 'host: "127.0.0.1"' in y and 'port: 8317' in y
assert 'openai-compatibility:' in y and 'base-url: "https://api.kimi.com/coding/v1"' in y
assert 'api-key: "kimi-test-key"' in y and 'name: "kimi-k3"' in y and 'alias: "kimi-k3"' in y
pl=plistlib.loads(render('config/examples/local.claudex-local.model-filter.plist.template').encode())
assert pl['Label']=='local.claudex-local.model-filter'
assert pl['EnvironmentVariables']['CLAUDEX_LOCAL_COMPACTION_MODEL']==roles['compaction']['model']
agents=list((r/'agents').glob('*.md')); assert len(agents)>=6
actual={}
for a in agents:
 t=a.read_text(); assert t.startswith('---') and 'model:' in t and 'tools:' in t
 frontmatter=t.split('---',2)[1]
 name_match=re.search(r'^name:\s*(\S+)\s*$',frontmatter,re.M)
 model_match=re.search(r'^model:\s*(\S+)\s*$',frontmatter,re.M)
 assert name_match and model_match,a
 name=name_match.group(1); model=model_match.group(1)
 assert name not in actual,f'duplicate agent name: {name}'
 actual[name]=model
 assert not re.search(r'^model:\s*gpt-5\.6\s*$',frontmatter,re.M),a
agent_roles=[role for role in roles.values() if role.get('agent') is not None]
expected={role['agent']:role['model'] for role in agent_roles}
assert len(expected)==len(agent_roles),'duplicate agent in models.json'
assert set(actual)==set(expected),f'agent set mismatch: actual={sorted(actual)} expected={sorted(expected)}'
for name,model in expected.items(): assert actual[name]==model,f'{name}: agent={actual[name]} models.json={model}'
alltext='\n'.join(p.read_text(errors='ignore') for p in r.rglob('*') if p.is_file() and '.git' not in p.parts and p.as_posix() != 'scripts/verify.sh')
for pattern in [r'\bsk-[A-Za-z0-9_-]{20,}\b',r'\bsk-kimi-[A-Za-z0-9_-]{10,}\b',r'\bgh[opsu]_[A-Za-z0-9]{20,}\b',r'\beyJ[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{10,}']:
 assert not re.search(pattern,alltext)
for forbidden in ['internal/mcpserver','claudex-workflow.v1.7.9']:
 assert forbidden not in alltext,forbidden
launcher=(r/'scripts/claudex-local').read_text()
for isolation in ['--setting-sources user,project,local','--strict-mcp-config','--disallowedTools "Skill,mcp__*"']:
 assert isolation in launcher,isolation
print('static verification: PASS')
PY2
