# Sub-Agent Guardrails

Rules enforced on every dispatched TDD sub-agent.

## Tool Allowlist

Always pass `--allowedTools` explicitly. Sub-agents do NOT inherit Bash permissions from
the parent session. Minimum required set:

```
Read, Write, Bash, Grep, Glob
```

Add `Edit` if the agent will be patching existing files (common). Do not add `Agent`
(no nested orchestration).

## Concurrency Cap

Maximum **5 concurrent agents**. Track running slots in the dispatcher. When a slot frees,
dispatch the next queued crate. See `helpers/dispatch.sh` for the reference implementation.

## Crate Isolation

Never dispatch two agents for the same crate simultaneously. One agent owns one crate for
the duration of its run. If two tasks target the same crate, assign both to a single agent
and have it work them sequentially.

## Commit Verification

After each agent completes, verify it committed:

```bash
git log --oneline -3   # or check the worktree branch
```

Sub-agents frequently complete tasks but forget to commit. If no commit is found, treat
the agent run as incomplete and re-issue the commit instruction.

## Worktree Isolation (Optional but Recommended)

Set `isolation: "worktree"` on the Agent tool call to give each sub-agent a clean git
worktree. This prevents branch conflicts when multiple agents modify different crates.
After all agents complete, cherry-pick commits sequentially into the main branch:

```bash
# Collect commits from each worktree branch
git cherry-pick <sha1> <sha2> ...
```

Never use octopus merges across sub-agent branches.

## BLOCKED.md Protocol

If an agent writes `BLOCKED.md`, do not retry it. Read the file, extract the blocker,
and surface it to the user. The 3-attempt limit is absolute — do not override it by
re-dispatching the same agent with the same task.

## Environment / Secrets

Sub-agents cannot resolve `op://` URIs. If a crate's tests require secrets:

1. Resolve them in the parent session with `op read`.
2. Pass concrete values via environment injection:
   ```bash
   op run --env-file=~/.secrets -- cargo nextest run -p <crate>
   ```
3. Document the required env vars in the agent prompt so the agent knows to expect them.

## SOLID Architecture Enforcement

Sub-agents implementing Rust code MUST follow SOLID/hexagonal architecture principles.
This is non-negotiable for any new module or significant addition. See
`references/solid-principles.md` for the full ruleset.

### Summary of enforcement points

- **New external dependency** → define a trait (port) in the domain layer first.
- **New implementation** → create an adapter in `infra/` or equivalent; do not put
  infrastructure code in domain files.
- **Business logic** → lives in the domain layer, generic over trait bounds; never in
  adapters.
- **Composition root** (`main.rs` or equivalent) → the only place that names concrete
  adapter types.
- **Tests** → mock at trait boundaries using in-memory test doubles; never mock the
  database or external APIs directly in unit tests.
- **Trait size** → follow ISP: small, focused traits. If a trait has more than ~5 methods,
  consider splitting it.
- **Error types** → define domain error enums; adapters map infrastructure errors to
  domain errors before returning.

### Checklist for every crate agent

Before committing, the agent MUST verify:

- [ ] No infrastructure types leak into domain structs or function signatures.
- [ ] Every new external system interaction is behind a trait.
- [ ] `cargo clippy -p <crate> -- -D warnings` is clean.
- [ ] `cargo nextest run -p <crate>` passes (all tests green).
- [ ] The failing test was written and confirmed red before implementation started.
