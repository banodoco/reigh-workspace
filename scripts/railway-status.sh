#!/bin/bash
# Railway workspace status dashboard
# Shows latest deployment status for all services across all projects
#
# Usage:
#   railway-status.sh              # Show all services (3 deploys each)
#   railway-status.sh --reigh      # Reigh services only
#   railway-status.sh --banodoco   # Banodoco services only
#   railway-status.sh --personal   # Personal services only

RAILWAY_CONFIG="$HOME/.railway/config.json"
WORKSPACE_ID="3837620e-0264-468d-bf1f-53739f9b9d9f"
FILTER="${1:-all}"

if [ ! -f "$RAILWAY_CONFIG" ]; then
    echo "Railway config not found at $RAILWAY_CONFIG — run 'railway login' first"
    exit 1
fi

RAILWAY_TOKEN=$(python3 -c "import json; print(json.load(open('$RAILWAY_CONFIG')).get('user',{}).get('token',''))" 2>/dev/null)
if [ -z "$RAILWAY_TOKEN" ]; then
    echo "No Railway token found — run 'railway login' first"
    exit 1
fi

curl -s -X POST https://backboard.railway.app/graphql/v2 \
  -H "Authorization: Bearer $RAILWAY_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"query\": \"{ workspace(workspaceId: \\\"$WORKSPACE_ID\\\") { projects { edges { node { id name services { edges { node { id name repoTriggers { edges { node { repository } } } deployments(first: 3) { edges { node { status createdAt } } } } } } } } } } }\"}" | python3 -c "
import json, sys
from datetime import datetime, timezone

filter_arg = '$FILTER'

GROUPS = {
    'reigh': {
        'label': 'Reigh',
        'projects': {'Reigh', 'gpu-orchestrator', 'api-orchestrator'},
    },
    'banodoco': {
        'label': 'Banodoco',
        'projects': {'ARTCOMPUTE', 'Banodoco Website', 'Arca Gidan', 'ADOS', 'bndc', 'desloppify-website'},
    },
    'personal': {
        'label': 'Personal',
        'projects': {'Arnold', 'pom.voyage', 'InData'},
    },
}

data = json.load(sys.stdin)
if 'errors' in data:
    print('API error:', json.dumps(data['errors']))
    sys.exit(1)

projects = data['data']['workspace']['projects']['edges']

def format_age(iso_str):
    try:
        created = datetime.fromisoformat(iso_str.replace('Z', '+00:00'))
        age = datetime.now(timezone.utc) - created
        if age.days > 30:
            return f'{age.days // 30}mo ago'
        elif age.days > 0:
            return f'{age.days}d ago'
        elif age.seconds > 3600:
            return f'{age.seconds // 3600}h ago'
        else:
            return f'{age.seconds // 60}m ago'
    except Exception:
        return ''

def status_icon(status):
    return {'SUCCESS': '+', 'BUILDING': '~', 'FAILED': 'X', 'DEPLOYING': '>', 'CRASHED': '!', 'REMOVED': '-'}.get(status, '?')

def format_service(proj, svc):
    deps = svc['deployments']['edges']
    lines = []
    if not deps:
        lines.append(f'  [?] {proj[\"name\"]:25s} {svc[\"name\"]:25s} (no deploys)')
        return lines

    # First deploy gets the full project/service name
    d = deps[0]['node']
    icon = status_icon(d['status'])
    age = format_age(d['createdAt'])
    lines.append(f'  [{icon}] {proj[\"name\"]:25s} {svc[\"name\"]:25s} {d[\"status\"]:10s} {age}')

    # Subsequent deploys are indented under
    for dep in deps[1:]:
        d2 = dep['node']
        icon2 = status_icon(d2['status'])
        age2 = format_age(d2['createdAt'])
        lines.append(f'      {\"\":25s} {\"\":25s} [{icon2}] {d2[\"status\"]:10s} {age2}')

    return lines

# Build lookup
proj_lookup = {}
for p in projects:
    proj = p['node']
    proj_lookup[proj['name']] = p

# Determine which groups to show
if filter_arg.lstrip('-') in GROUPS:
    groups_to_show = [filter_arg.lstrip('-')]
elif filter_arg == 'all':
    groups_to_show = list(GROUPS.keys())
else:
    print(f'Unknown filter: {filter_arg}')
    print(f'Usage: railway-status.sh [--reigh|--banodoco|--personal|all]')
    sys.exit(1)

print()

for group_key in groups_to_show:
    group = GROUPS[group_key]
    lines = []
    for proj_name in sorted(group['projects'], key=str.lower):
        if proj_name not in proj_lookup:
            continue
        proj = proj_lookup[proj_name]['node']
        for s in proj['services']['edges']:
            lines.extend(format_service(proj, s['node']))

    if lines:
        print(f'{group[\"label\"]}')
        print('-' * 75)
        for line in lines:
            print(line)
        print()

# Show ungrouped if showing all
if filter_arg == 'all':
    ungrouped = []
    all_grouped = set()
    for g in GROUPS.values():
        all_grouped |= g['projects']
    for p in projects:
        proj = p['node']
        if proj['name'] not in all_grouped:
            for s in proj['services']['edges']:
                ungrouped.extend(format_service(proj, s['node']))
    if ungrouped:
        print('Other')
        print('-' * 75)
        for line in ungrouped:
            print(line)
        print()
" 2>&1
