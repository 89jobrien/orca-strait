# SOLID / Hexagonal Architecture for Sub-Agents

Every TDD sub-agent dispatched by this plugin MUST produce code that follows these
principles. This file is the authoritative reference — agents should read it before
writing any implementation code.

## Architecture Layers

```
Composition Root (main.rs)
        │
        ▼
Domain Layer          ← traits (ports) + domain types + business logic
        ▲
        │
    implements
        │
Infrastructure Adapters  ← one per external system (HTTP, DB, file, API)
```

Dependencies point **inward only**. Adapters depend on domain traits. Domain depends on
nothing outside itself.

## Domain Layer Rules

1. **Zero external crate dependencies** in domain files. No `reqwest`, no `sqlx`, no
   `tokio` (use `async_trait` only if the trait itself needs async).
2. Define one trait per external boundary (the "port"):
   ```rust
   // domain.rs
   pub trait IssueTracker {
       fn open_issues(&self) -> Result<Vec<Issue>, TrackerError>;
   }
   ```
3. Define domain types separately from infrastructure types:
   ```rust
   pub struct Issue { pub id: u64, pub title: String, pub body: String }
   pub enum TrackerError { NotFound, Network, Auth }
   ```
4. Business logic is generic over trait bounds:
   ```rust
   pub struct Planner<T: IssueTracker> { tracker: T }
   impl<T: IssueTracker> Planner<T> {
       pub fn next_tasks(&self) -> Result<Vec<Task>, TrackerError> { ... }
   }
   ```

## Adapter Rules

1. One struct per external system. File lives in `infra/` (or `adapters/`).
2. Implement the domain trait. Map all external errors to domain errors:
   ```rust
   impl IssueTracker for GitHubAdapter {
       fn open_issues(&self) -> Result<Vec<Issue>, TrackerError> {
           self.client.fetch_issues()
               .map_err(|e| match e {
                   GhError::Auth => TrackerError::Auth,
                   _ => TrackerError::Network,
               })
       }
   }
   ```
3. Never put business logic in adapters. Validation and rules live in the domain.
4. For testing, provide an `InMemory` adapter:
   ```rust
   pub struct InMemoryIssueTracker { pub issues: Vec<Issue> }
   impl IssueTracker for InMemoryIssueTracker {
       fn open_issues(&self) -> Result<Vec<Issue>, TrackerError> {
           Ok(self.issues.clone())
       }
   }
   ```

## Interface Segregation

Prefer small, focused traits over large ones:

```rust
// Too large — split it
pub trait Storage {
    fn read(&self, key: &str) -> Result<Vec<u8>, Error>;
    fn write(&self, key: &str, data: &[u8]) -> Result<(), Error>;
    fn delete(&self, key: &str) -> Result<(), Error>;
    fn list(&self) -> Result<Vec<String>, Error>;
}

// Better
pub trait Reader { fn read(&self, key: &str) -> Result<Vec<u8>, Error>; }
pub trait Writer { fn write(&self, key: &str, data: &[u8]) -> Result<(), Error>; }
```

Components depend only on the traits they actually use.

## Composition Root

`main.rs` (or the binary entry point) is the **only** place that names concrete adapter
types. It wires domain structs to adapters:

```rust
fn main() {
    let tracker = GitHubAdapter::new(std::env::var("GH_TOKEN").unwrap());
    let planner = Planner::new(tracker);
    run(planner);
}
```

## Testing Strategy

| Test type | What to mock | Tool |
|-----------|-------------|------|
| Unit | Domain logic | `InMemory*` adapters |
| Integration | Adapters | Real system / test instance |
| Property | Domain invariants | `proptest` |

Never mock at the HTTP level in unit tests. Always mock at the trait boundary using
in-memory test doubles.

## Async Traits

Use `async_trait` for async ports:

```rust
use async_trait::async_trait;

#[async_trait]
pub trait LlmProvider {
    async fn complete(&self, prompt: &str) -> Result<String, LlmError>;
}

#[async_trait]
impl LlmProvider for OpenAiAdapter {
    async fn complete(&self, prompt: &str) -> Result<String, LlmError> { ... }
}
```

## Error Handling

Define domain error enums. Never expose `reqwest::Error`, `sqlx::Error`, etc. to the
domain layer. Adapters convert:

```rust
#[derive(Debug)]
pub enum PlannerError { Unauthorized, NotFound, Internal(String) }

// In adapter
.map_err(|e| PlannerError::Internal(e.to_string()))
```

## Common Mistakes (Do Not Repeat)

| Mistake | Fix |
|---------|-----|
| Trait mirrors external API (Stripe fields in domain) | Redefine trait with domain types |
| Business validation in adapter | Move to domain service |
| Domain imports `reqwest` | Extract to adapter |
| Generic parameter explosion (4+ type params) | Use `Box<dyn Trait>` or a deps struct |
| `clone()` on large infra types to satisfy trait | Use `Arc<dyn Trait>` in service |

## When to Skip This Pattern

- Spike / throwaway prototype
- Single-file utility scripts
- Hot paths where vtable dispatch is measured to be too slow

In all other cases, hexagonal architecture is the default.
