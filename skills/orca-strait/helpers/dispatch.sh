#!/usr/bin/env bash
# dispatch.sh — Print the crate batches for parallel sub-agent dispatch.
#
# Reads the task list JSON from stdin (output of decompose.sh) and groups
# independent tasks by crate, then prints batches of up to 5 crates.
# The orchestrator uses this to know which crates to dispatch in each wave.
#
# Usage:
#   ./helpers/decompose.sh | ./helpers/dispatch.sh
#
# Output: one line per batch, JSON array of {crate, tasks[]} objects.
# Wave 1 = first 5 independent crates (highest priority).
# Wave 2 = next 5, etc.
# Blocked crates are listed last with a "blocked" flag.

set -euo pipefail

python3 -c "
import json, sys

tasks = json.load(sys.stdin)

# Group by crate
from collections import defaultdict
by_crate = defaultdict(list)
for t in tasks:
    by_crate[t['crate']].append(t)

# Separate independent vs blocked
independent = []
blocked = []
seen_crates = set()

for crate, crate_tasks in by_crate.items():
    all_independent = all(t['independent'] for t in crate_tasks)
    priority = min(t['priority'] for t in crate_tasks)
    entry = {
        'crate': crate,
        'tasks': [t['task'] for t in crate_tasks],
        'priority': priority,
        'blocked': not all_independent,
        'blocked_by': list(set(b for t in crate_tasks for b in t.get('blocked_by', [])))
    }
    if all_independent:
        independent.append(entry)
    else:
        blocked.append(entry)

# Sort independent by priority
independent.sort(key=lambda x: x['priority'])

# Emit waves of 5
WAVE_SIZE = 5
waves = [independent[i:i+WAVE_SIZE] for i in range(0, len(independent), WAVE_SIZE)]

print('=== DISPATCH PLAN ===')
for i, wave in enumerate(waves, 1):
    print(f'Wave {i} ({len(wave)} crates):')
    for entry in wave:
        print(f'  [{entry[\"priority\"]}] {entry[\"crate\"]}')
        for task in entry['tasks']:
            print(f'      - {task}')

if blocked:
    print()
    print(f'Blocked ({len(blocked)} crates — dispatch after dependencies complete):')
    for entry in blocked:
        print(f'  {entry[\"crate\"]} (waiting on: {entry[\"blocked_by\"]})')
        for task in entry['tasks']:
            print(f'      - {task}')

print()
print('=== JSON OUTPUT ===')
output = {
    'waves': waves,
    'blocked': blocked
}
print(json.dumps(output, indent=2))
"
