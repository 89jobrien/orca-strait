#!/usr/bin/env bash
# decompose.sh — Parse .ctx/git/issues/open.json + HANDOFF.* + PLAN.md
# into a JSON task list matching templates/task-list.json schema.
#
# Usage: ./helpers/decompose.sh [repo_root]
# Output: JSON array to stdout

set -euo pipefail

REPO="${1:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
ISSUES="$REPO/.ctx/git/issues/open.json"
TASKS="[]"

# ── Workspace crate names ────────────────────────────────────────────────────
CRATES=$(cargo metadata --manifest-path "$REPO/Cargo.toml" \
  --no-deps --format-version 1 2>/dev/null \
  | python3 -c "import sys,json; d=json.load(sys.stdin); print('\n'.join(p['name'] for p in d['packages']))" \
  || echo "")

# ── Helper: resolve crate from text ─────────────────────────────────────────
resolve_crate() {
  local text="$1"
  # First: explicit crate: label pattern
  echo "$text" | python3 -c "
import sys, re
text = sys.stdin.read()
m = re.search(r'crate:([a-z0-9_-]+)', text)
if m:
    print(m.group(1))
    sys.exit(0)
# Fallback: scan for known crate names
crates = '''$CRATES'''.strip().splitlines()
for c in crates:
    if c and c in text:
        print(c)
        sys.exit(0)
print('unknown')
"
}

# ── Parse HANDOFF.* (highest priority) ──────────────────────────────────────
for hf in "$REPO"/HANDOFF.*; do
  [ -f "$hf" ] || continue
  ext="${hf##*.}"
  if [ "$ext" = "yaml" ] || [ "$ext" = "yml" ]; then
    # Parse next[] items from YAML
    python3 -c "
import sys, json
try:
    import yaml
    with open('$hf') as f:
        d = yaml.safe_load(f)
    tasks = []
    for item in (d or {}).get('next', []):
        tasks.append({
            'crate': item.get('crate', 'unknown'),
            'task': item.get('task', ''),
            'source': 'handoff',
            'source_id': 'next',
            'independent': True,
            'blocked_by': [],
            'priority': 1
        })
    # Mark blocked items
    blocked_crates = set()
    for item in (d or {}).get('blocked', []):
        blocked_crates.add(item.get('crate', ''))
    for t in tasks:
        if t['crate'] in blocked_crates:
            t['independent'] = False
    print(json.dumps(tasks))
except Exception as e:
    print('[]', file=sys.stderr)
    print('[]')
"
  elif [ "$ext" = "md" ]; then
    python3 -c "
import sys, json, re
with open('$hf') as f:
    content = f.read()
tasks = []
# Parse ## Next section
m = re.search(r'## Next\n(.*?)(?=\n##|\Z)', content, re.DOTALL)
if m:
    for line in m.group(1).strip().splitlines():
        line = line.lstrip('- ').strip()
        if not line:
            continue
        crate_m = re.search(r'crate:\s*(\S+)', line)
        crate = crate_m.group(1) if crate_m else 'unknown'
        tasks.append({
            'crate': crate,
            'task': line,
            'source': 'handoff',
            'source_id': 'next',
            'independent': True,
            'blocked_by': [],
            'priority': 1
        })
print(json.dumps(tasks))
"
  fi
done | python3 -c "
import sys, json
all_tasks = []
for line in sys.stdin:
    line = line.strip()
    if line.startswith('['):
        try:
            all_tasks.extend(json.loads(line))
        except:
            pass
print(json.dumps(all_tasks))
" > /tmp/_handoff_tasks.json

# ── Parse open GitHub issues ─────────────────────────────────────────────────
if [ -f "$ISSUES" ]; then
  python3 -c "
import sys, json, re
with open('$ISSUES') as f:
    issues = json.load(f)
tasks = []
for issue in issues:
    labels = [l['name'] for l in issue.get('labels', [])]
    crate = 'unknown'
    for label in labels:
        m = re.match(r'crate:(.+)', label)
        if m:
            crate = m.group(1)
            break
    tasks.append({
        'crate': crate,
        'task': issue['title'],
        'source': 'issue',
        'source_id': issue['number'],
        'independent': True,
        'blocked_by': [],
        'priority': 3
    })
print(json.dumps(tasks))
" > /tmp/_issue_tasks.json
else
  echo "[]" > /tmp/_issue_tasks.json
fi

# ── Merge and deduplicate ─────────────────────────────────────────────────────
python3 -c "
import json

with open('/tmp/_handoff_tasks.json') as f:
    handoff = json.load(f)
with open('/tmp/_issue_tasks.json') as f:
    issues = json.load(f)

seen = set()
merged = []
for t in handoff + issues:
    key = (t['crate'], t['task'][:60])
    if key not in seen:
        seen.add(key)
        merged.append(t)

# Sort: priority asc, then crate name
merged.sort(key=lambda t: (t['priority'], t['crate']))
print(json.dumps(merged, indent=2))
"

# Cleanup
rm -f /tmp/_handoff_tasks.json /tmp/_issue_tasks.json
