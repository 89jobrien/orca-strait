---
name: orca-strait
description: >
  This skill should be used when the user asks to "run TDD agents", "orchestrate crate
  implementations", "spawn parallel test agents", "implement the plan with sub-agents",
  "run the handoff", "work through the issues", "implement open tasks in parallel",
  or any phrasing that implies reading issues/handoffs and dispatching per-crate sub-agents
  that write failing tests first. Also triggers on "/orca-strait".
version: 0.1.0
---

# Orca Strait

Parallel TDD sub-agent orchestrator for Rust workspaces. Read context sources (GitHub
issues, handoff files, implementation plans), decompose work by crate, spawn independent
agents with strict test-first discipline, then integrate the results.

## Overview

The orchestration flow has four stages:

1. **Gather context** — sync issues to `.ctx/`, read all `HANDOFF.*` files, read the
   implementation plan.
2. **Decompose** — extract tasks, group by crate, mark independent vs. blocked.
3. **Dispatch** — spawn one sub-agent per independent crate (max 5 concurrent).
4. **Integrate** — after all agents complete, run the full workspace suite and fix
   integration failures.

## Stage 1: Gather Context

### Sync GitHub Issues

```bash
mkdir -p .ctx/git/issues
gh issue list --state open --json number,title,body,labels,assignees \
  > .ctx/git/issues/open.json
```

Parse `open.json` for task extraction in Stage 2. The file is the canonical source of
truth — do not re-query GitHub during decomposition.

### Find Handoff Files

```bash
# Glob pattern — picks up HANDOFF.yaml, HANDOFF.md, HANDOFF.json, etc.
ls HANDOFF.* 2>/dev/null
```

Read every file matching `HANDOFF.*` in the repo root. These are written by other agents
and contain current state, blocked items, and next steps.

### Find the Implementation Plan

Look for these files in order (first found wins):

1. `PLAN.md`
2. `IMPLEMENTATION.md`
3. `.ctx/plan.md`
4. Any file matching `*PLAN*.md` in repo root

If none exist, derive the plan from issues + handoff content.

## Stage 2: Decompose by Crate

Parse all context into a task list. For each task:

- Identify the **target crate** (`-p <crate>` argument for `cargo nextest`).
- Mark as **independent** if it touches only one crate and has no cross-crate dependencies.
- Mark as **blocked** if it depends on another in-progress task.

Independent tasks at the same crate level can run in parallel. Tasks that share a crate
must run sequentially within that crate's agent.

Use the task decomposition template:

```
helpers/decompose.sh  — prints a JSON task list from .ctx/git/issues/open.json
```

See `templates/task-list.json` for the schema.

## Stage 3: Dispatch Sub-Agents

Spawn one `Agent` tool call per independent crate, up to **5 concurrent**. Each agent
receives this exact instruction set (see `templates/agent-prompt.md` for the full
template):

```
You are a TDD implementation agent for crate: <CRATE_NAME>

Tasks assigned: <TASK_LIST>

Workflow (follow exactly — do not skip steps):
1. Read only the source files in crates/<CRATE_NAME>/ relevant to the tasks.
2. For each task:
   a. Write a FAILING test that captures the requirement.
   b. Run: cargo nextest run -p <CRATE_NAME> -- <test_name>
      Confirm it fails. If it passes already, the task may already be done — verify.
   c. Implement the minimum code to make the test pass.
   d. Run: cargo nextest run -p <CRATE_NAME>
      All tests must pass before moving to the next task.
   e. Run: cargo clippy -p <CRATE_NAME> -- -D warnings
      Fix every warning. Commit only when clippy is clean.
3. If stuck after 3 attempts on any single task:
   a. Write BLOCKED.md at the repo root describing what was attempted and why it failed.
   b. Stop. Do not proceed to other tasks.
4. After all tasks pass: commit with message "feat(<CRATE_NAME>): <summary>".
```

Enforce the 5-agent cap strictly. If there are more than 5 independent crates, queue
the remainder and dispatch each as a running slot frees up.

Reference: `helpers/dispatch.sh` — wraps the Agent dispatch loop with slot tracking.

## Stage 4: Integrate

After all agents report completion:

1. Verify each agent committed (`git log --oneline -5` per crate branch, or check
   worktrees if using `isolation: worktree`).
2. Run the full workspace suite:
   ```bash
   cargo nextest run --workspace
   ```
3. If failures exist, they are integration failures (cross-crate). Fix them directly
   in the orchestrator session — do not spawn another agent layer.
4. Run `cargo clippy --workspace -- -D warnings` and fix any remaining warnings.
5. Summarize: list tasks completed, tasks blocked, and any integration fixes applied.

## Guardrails

- **Never skip the failing-test step.** An implementation without a prior failing test
  is not TDD and must be rejected.
- **Cap concurrent agents at 5.** Exceeding this triggers API rate limits.
- **BLOCKED.md stops the agent.** Do not attempt recovery loops beyond 3 tries.
- **Agents do not inherit Bash permissions.** Always pass `--allowedTools` when
  dispatching. Minimum set: `Read,Write,Bash,Grep,Glob`.
- **Crate isolation is the unit of parallelism.** Never dispatch two agents for the
  same crate simultaneously.

## Quick Reference

| Step | Command |
|------|---------|
| Sync issues | `gh issue list --state open --json ... > .ctx/git/issues/open.json` |
| List handoffs | `ls HANDOFF.*` |
| Run crate tests | `cargo nextest run -p <crate>` |
| Run workspace | `cargo nextest run --workspace` |
| Clippy strict | `cargo clippy --workspace -- -D warnings` |
| Check commits | `git log --oneline -5` |

## Additional Resources

- **`references/context-sources.md`** — Detailed schema for issues JSON, handoff YAML,
  and plan file formats.
- **`references/agent-guardrails.md`** — Full list of sub-agent restrictions, tool
  allowlists, and failure modes.
- **`references/tdd-discipline.md`** — Red/green/refactor cycle, when to skip steps
  (almost never), and common TDD anti-patterns in Rust.
- **`helpers/decompose.sh`** — Parse issues JSON into a structured task list.
- **`helpers/dispatch.sh`** — Dispatch loop with 5-agent concurrency cap.
- **`templates/agent-prompt.md`** — Full sub-agent instruction template (copy verbatim).
- **`templates/task-list.json`** — JSON schema for the decomposed task list.
