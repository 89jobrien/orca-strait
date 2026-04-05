# TDD Discipline for Rust Sub-Agents

## The Red/Green/Refactor Cycle

Every task follows exactly this sequence. No shortcuts.

```
RED   → write a failing test that captures the requirement
GREEN → write the minimum code to make it pass
CLEAN → refactor (rename, extract, simplify) without breaking tests
```

### RED: Writing the Failing Test

1. Identify the observable behavior the task requires.
2. Write a test that asserts that behavior.
3. **Run the test and confirm it fails.** A test that passes immediately without
   implementation means either the feature already exists (verify and close the task)
   or the test is testing the wrong thing.

```rust
#[test]
fn retry_adapter_retries_on_transient_error() {
    let mut calls = 0;
    let adapter = FlakyAdapter::new(|_| {
        calls += 1;
        if calls < 3 { Err(AdapterError::Transient) } else { Ok(()) }
    });
    let retry = RetryAdapter::new(adapter, 3);
    assert!(retry.execute().is_ok());
    assert_eq!(calls, 3);
}
```

Run: `cargo nextest run -p <crate> -- retry_adapter_retries_on_transient_error`
Expected output: `FAILED` (test must fail before implementation).

### GREEN: Minimum Implementation

Write only the code needed to pass the test. Resist adding features or
"obvious improvements" — those go in a separate task with their own test.

```rust
pub struct RetryAdapter<A> { inner: A, max: usize }
impl<A: Port> RetryAdapter<A> {
    pub fn new(inner: A, max: usize) -> Self { Self { inner, max } }
    pub fn execute(&self) -> Result<(), AdapterError> {
        for _ in 0..self.max {
            match self.inner.call() {
                Ok(v) => return Ok(v),
                Err(AdapterError::Transient) => continue,
                Err(e) => return Err(e),
            }
        }
        Err(AdapterError::MaxRetriesExceeded)
    }
}
```

Run: `cargo nextest run -p <crate>` — all tests green.

### CLEAN: Refactor

Only after all tests are green:
- Rename variables/types for clarity.
- Extract helpers if logic is duplicated.
- Run clippy: `cargo clippy -p <crate> -- -D warnings`.
- Tests must still pass after every refactor step.

## Anti-Patterns to Avoid

| Anti-pattern | Why it's wrong | Fix |
|--------------|---------------|-----|
| Write implementation first, test after | Test will be written to fit the code, not the behavior | Always RED first |
| `#[allow(dead_code)]` on new code | Hides unused paths | Remove unused code or write a test for it |
| Testing internal implementation details | Tests break on refactor | Test observable behavior only |
| `unwrap()` in production code | Panics in tests mask real errors | Return `Result`, propagate errors |
| Asserting on log output | Logs are not API | Assert on return values / state |
| One massive test | Hard to diagnose failures | One behavior per test |

## Rust-Specific Patterns

### Test Doubles Without Mockall

Prefer hand-written in-memory adapters over `mockall`. They are simpler, portable,
and follow the hexagonal architecture pattern:

```rust
// In the crate's test module or tests/helpers.rs
pub struct InMemoryStorage { pub entries: std::collections::HashMap<String, Vec<u8>> }

impl StoragePort for InMemoryStorage {
    fn read(&self, key: &str) -> Result<Vec<u8>, StorageError> {
        self.entries.get(key).cloned().ok_or(StorageError::NotFound)
    }
    fn write(&self, key: &str, data: &[u8]) -> Result<(), StorageError> {
        self.entries.insert(key.to_owned(), data.to_vec());
        Ok(())
    }
}
```

### Testing Async Code

```rust
#[tokio::test]
async fn provider_returns_completion() {
    let provider = InMemoryLlm { response: "hello".to_string() };
    let result = provider.complete("say hello").await.unwrap();
    assert_eq!(result, "hello");
}
```

### Property-Based Tests for Domain Invariants

Use `proptest` for invariants that should hold for all inputs:

```rust
proptest! {
    #[test]
    fn payment_amount_never_negative(cents in 0u64..1_000_000) {
        let p = Payment { amount_cents: cents, currency: "USD".to_string() };
        assert!(p.amount_cents >= 0);
    }
}
```

## The 3-Attempt Rule

If a test is still failing after 3 implementation attempts:

1. Write `BLOCKED.md` at the repo root.
2. Include: crate name, task description, all three approaches tried, exact error output.
3. Stop. Do not attempt a 4th approach.

This rule exists to prevent agents from spinning indefinitely on ambiguous requirements.
The blocker surfaces to the human for resolution.
