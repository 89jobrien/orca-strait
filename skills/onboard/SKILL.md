---
name: onboard
description: Use when the user says "onboard me", "set up orca-strait", "what does orca-strait
  do", "walk me through setup", or invokes /orca-strait:onboard. Guides through installation,
  prerequisites, and first orchestration run.
---

# onboard — orca-strait plugin setup

## Overview

**orca-strait** orchestrates parallel TDD sub-agents across a Rust workspace:

1. Reads open GitHub issues, `HANDOFF.*` files, and an implementation plan
2. Decomposes work by crate into a task list
3. Dispatches independent `tdd-crate-agent` sub-agents in waves (≤5 concurrent)
4. Each agent follows strict red/green/refactor discipline and SOLID/hexagonal architecture
5. Integrates results with `cargo nextest` + `cargo clippy` gates

## Step 1: Prerequisites

```bash
which claude cargo gh python3
cargo install cargo-nextest 2>/dev/null || echo "already installed"
gh auth status
```

- `claude` — Claude Code CLI (required)
- `cargo` + `cargo-nextest` — Rust test runner (required)
- `gh` — GitHub CLI, authenticated (required for issue reading)
- `python3` — used by `decompose.sh` (ships with macOS)

If any are missing, `just init` will prompt before continuing.

## Step 2: Clone and Init

```bash
git clone https://github.com/89jobrien/orca-strait ~/dev/orca-strait
cd ~/dev/orca-strait
just init
```

`just init` will:
1. Set `core.hooksPath = .githooks` for auto-reinstall on source changes
2. Check for `cargo`, `gh`, and `python3` — prompts if missing
3. Register the local plugin marketplace
4. Install the plugin via `claude plugin install orca-strait@local`

## Step 3: Prepare Your Workspace

orca-strait requires a Rust workspace with:

```
<repo>/
├── Cargo.toml          # [workspace] with members = [...]
├── HANDOFF.*.yaml      # optional — open items become tasks
└── PLAN.md             # optional — implementation plan
```

Open GitHub issues are fetched automatically via `gh issue list`.

## Step 4: Run

In a Claude session inside your Rust workspace:

```
/orca-strait
```

Or with flags:

```
/orca-strait --dry-run        # show task decomposition without dispatching
/orca-strait /path/to/repo    # explicit repo path
```

Expected: Claude surfaces the task list, asks for confirmation, then dispatches agents by wave.

## Architecture Enforcement

Every sub-agent is instructed to follow SOLID/hexagonal architecture:
- New external dependencies → trait (port) in domain layer first
- Implementations → adapters in `infra/`
- Business logic generic over traits
- Tests use in-memory doubles, never mocked HTTP/DB

If an agent is blocked after 3 attempts, it writes `BLOCKED.md` and stops.
The `check-blocked` hook surfaces this immediately to your session.

## Onboarding Complete

> Run `/orca-strait` in any Rust workspace with open issues or a HANDOFF file.
> Use `--dry-run` first to preview the task decomposition.
