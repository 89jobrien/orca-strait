---
name: orca-strait
description: >
  Orchestrate parallel TDD sub-agents across a Rust workspace. Reads open GitHub issues,
  HANDOFF.* files, and the implementation plan; decomposes work by crate; spawns
  independent agents with strict test-first discipline; then integrates results.
argument-hint: "[repo_path] [--dry-run]"
allowed-tools:
  - Bash
  - Read
  - Glob
  - Grep
  - Agent
---

# Orca Strait

Load and follow the full workflow from the `orca-strait` skill. The skill is at:

```
~/.claude/plugins/orca-strait/skills/orca-strait/SKILL.md
```

## Arguments

- `repo_path` (optional) — path to the Rust workspace root. Defaults to the current
  working directory / git root.
- `--dry-run` — run decomposition and print the dispatch plan, but do not spawn agents.

## Execution Steps

1. Resolve the workspace root (argument or `git rev-parse --show-toplevel`).
2. Sync issues to `.ctx/git/issues/open.json` using `gh issue list`.
3. Read all `HANDOFF.*` files in the repo root.
4. Read the implementation plan (`PLAN.md`, `IMPLEMENTATION.md`, or `.ctx/plan.md`).
5. Run `helpers/decompose.sh` to produce the task list.
6. Run `helpers/dispatch.sh` to plan the dispatch waves.
7. If `--dry-run`, print the plan and stop.
8. Dispatch wave 1 (up to 5 concurrent agents) using the template in
   `templates/agent-prompt.md`. Each agent gets:
   - Its crate name
   - Its task list
   - The SOLID principles reference path
9. Wait for all wave 1 agents to complete. Verify commits.
10. Dispatch wave 2 (if any), then wave 3, etc.
11. After all waves complete, run:
    ```bash
    cargo nextest run --workspace
    cargo clippy --workspace -- -D warnings
    ```
12. Fix any integration failures directly. Summarize results.

## Tips

- Use `--dry-run` first on an unfamiliar repo to preview what will be dispatched.
- If an agent writes `BLOCKED.md`, surface it immediately — do not retry.
- Blocked crates (cross-crate deps) are dispatched automatically after their dependencies
  complete in the wave sequence.
- All agents enforce SOLID/hexagonal architecture. See
  `references/solid-principles.md` for the full ruleset.
