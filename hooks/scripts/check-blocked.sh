#!/usr/bin/env bash
# check-blocked.sh — After any Agent tool call, scan for new BLOCKED.md files
# and surface them to stdout so the orchestrator session sees them immediately.

ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
BLOCKED="$ROOT/BLOCKED.md"

if [ -f "$BLOCKED" ]; then
  echo ""
  echo "⚠ BLOCKED.md detected at: $BLOCKED"
  echo "--- BLOCKED content ---"
  head -30 "$BLOCKED"
  echo "---"
  echo "Surface this to the user before dispatching further agents."
fi
