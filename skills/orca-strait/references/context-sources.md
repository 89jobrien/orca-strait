# Context Source Formats

## GitHub Issues (`open.json`)

Produced by:
```bash
gh issue list --state open --json number,title,body,labels,assignees \
  > .ctx/git/issues/open.json
```

Schema (array of objects):
```json
[
  {
    "number": 42,
    "title": "Add retry logic to HttpAdapter",
    "body": "The HttpAdapter currently panics on transient network errors...",
    "labels": [{ "name": "bug" }, { "name": "crate:http-adapter" }],
    "assignees": [{ "login": "89jobrien" }]
  }
]
```

### Crate Extraction from Issues

Labels prefixed with `crate:` are the canonical signal for target crate:

```
crate:http-adapter  →  -p http-adapter
crate:mbx           →  -p mbx
```

If no `crate:` label, scan the issue title/body for crate names matching workspace members
(`cargo metadata --no-deps --format-version 1 | jq '[.packages[].name]'`).

## Handoff Files (`HANDOFF.*`)

Written by other agents. May be YAML, Markdown, or JSON. Always in the repo root.

### HANDOFF.yaml example

```yaml
status: in_progress
last_updated: "2026-04-03"
completed:
  - "feat(mbx): add retry logic"
blocked:
  - crate: devloop-core
    reason: "Waiting for upstream trait refactor"
    attempts: 2
next:
  - crate: mbx
    task: "Implement exponential backoff in RetryAdapter"
  - crate: devloop-api
    task: "Add OpenAPI spec generation"
notes: |
  The RetryAdapter trait is defined in domain.rs. The in-memory test double
  is missing — write it before implementing the real adapter.
```

### HANDOFF.md example

Freeform markdown. Parse the `## Blocked`, `## Next`, and `## Notes` sections.

### HANDOFF.json example

```json
{
  "next": [
    { "crate": "mbx", "task": "Add RetryAdapter" }
  ],
  "blocked": [],
  "notes": ""
}
```

## Implementation Plan

Look for (first match wins): `PLAN.md`, `IMPLEMENTATION.md`, `.ctx/plan.md`, `*PLAN*.md`.

### Expected structure

```markdown
# Implementation Plan

## Phase 1: Domain Refactor
- [ ] crate: mbx — extract StoragePort trait
- [ ] crate: devloop-core — remove direct sqlx dependency

## Phase 2: Adapter Layer
- [ ] crate: mbx — implement S3Adapter
- [ ] crate: mbx — implement InMemoryAdapter for tests
```

Checkboxes (`- [ ]`) indicate pending tasks; (`- [x]`) indicate done. Parse unchecked
items only.

## Merging Context Sources

When all three sources exist, merge with this priority:

1. **HANDOFF.* blocked list** — skip these crates entirely.
2. **HANDOFF.* next list** — highest priority tasks.
3. **PLAN.md unchecked items** — remaining planned work.
4. **GitHub issues** — any issue not already represented above.

Deduplicate by crate+task description. When the same task appears in multiple sources,
prefer the most specific description (handoff > plan > issue).
