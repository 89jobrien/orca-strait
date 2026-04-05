# orca-strait

Parallel sub-agent orchestrator for Rust workspaces.

Reads open GitHub issues, `HANDOFF.*` files, and an implementation plan; decomposes
work by crate; spawns independent sub-agents with strict test-first discipline and
hexagonal architecture enforcement; then integrates the results.

## Installation

```bash
claude plugin add github:89jobrien/orca-strait
```

## Components

| Component | Type | Purpose |
|-----------|------|---------|
| `orca-strait` | Skill + Command | Full workflow — gather context, decompose, dispatch, integrate |
| `tdd-crate-agent` | Agent | Per-crate TDD implementor |
| `check-blocked` | Hook (PostToolUse/Agent) | Surfaces BLOCKED.md immediately after any agent call |

## Usage

### Slash command

```
/orca-strait
/orca-strait /path/to/repo
/orca-strait --dry-run
```

### Prose (skill trigger)

> "Implement the open issues in parallel using TDD agents"
> "Run the handoff tasks across the workspace"
> "Spawn crate agents for the implementation plan"

## Workflow

```
gh issue list → .ctx/git/issues/open.json
HANDOFF.*   ──┐
PLAN.md     ──┴── decompose.sh → task list → dispatch.sh → waves
                                                │
                              ┌─────────────────┼──────────────────┐
                          Wave 1             Wave 2 ...          Blocked
                       (≤5 agents)        (after wave 1)    (after deps)
                              │
                         tdd-crate-agent × N
                         (RED → GREEN → CLEAN → commit)
                              │
                    cargo nextest --workspace
                    cargo clippy --workspace -- -D warnings
```

## Architecture Enforcement

Every sub-agent is required to follow SOLID/hexagonal architecture:

- New external dependencies → trait (port) in domain layer first
- Implementations → adapters in `infra/`
- Business logic → domain layer, generic over traits
- Tests → in-memory trait doubles, never mocked HTTP/DB
- Composition root → only place that names concrete adapters

See `skills/tdd-orchestrate/references/solid-principles.md` for the full ruleset.

## TDD Discipline

Each agent follows red/green/refactor strictly:

1. Write a failing test — confirm it fails before implementation
2. Implement minimum code to pass
3. Refactor + clippy clean
4. Commit

After 3 failed attempts on any task, the agent writes `BLOCKED.md` and stops.
The `check-blocked` hook surfaces this immediately to the orchestrator session.

## Prerequisites

- `gh` CLI authenticated (`gh auth status`)
- `cargo-nextest` installed (`cargo install cargo-nextest`)
- Rust workspace with a `Cargo.toml` at the root
- `python3` available (for decompose.sh parsing)

## File Layout

```
tdd-orchestrator/
├── .claude-plugin/plugin.json
├── commands/
│   └── orca-strait.md              # /orca-strait slash command
├── agents/
│   └── tdd-crate-agent.md          # per-crate TDD sub-agent
├── skills/
│   └── orca-strait/
│       ├── SKILL.md                # core workflow (auto-triggers on prose)
│       ├── references/
│       │   ├── context-sources.md  # issues/handoff/plan schemas
│       │   ├── agent-guardrails.md # sub-agent restrictions + SOLID checklist
│       │   ├── solid-principles.md # SOLID/hexagonal rules for Rust
│       │   └── tdd-discipline.md   # red/green/refactor + anti-patterns
│       ├── helpers/
│       │   ├── decompose.sh        # parse context → task list JSON
│       │   └── dispatch.sh        # group tasks → dispatch waves
│       └── templates/
│           ├── agent-prompt.md     # sub-agent instruction template
│           └── task-list.json      # task list JSON schema
└── hooks/
    ├── hooks.json
    └── scripts/
        └── check-blocked.sh        # surface BLOCKED.md after agent calls
```
