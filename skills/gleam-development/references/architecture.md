# Architecture

Load this when deciding where code should live, how errors should be
represented, or whether a boundary deserves an abstraction.

## Pure core, explicit edges

The default shape for a Gleam feature:

```
src/
  <domain>.gleam         pure types and rules (no IO, no time, no randomness)
  <domain>/<topic>.gleam more pure rules, grouped by concept
  <adapter>.gleam        talks to a store, a process, an HTTP client, a clock
  <app>.gleam            wires the adapter to the domain: the only impure layer
```

- Domain functions take values and return values. They are trivially testable
  and identical on both targets.
- Adapters receive what they need as arguments (a store value, a function, a
  connection) instead of reaching for globals. That is also how a
  database-backed workflow is tested without a database: pass an in-memory
  store with the same shape.
- The impure layer stays thin enough to read in one screen. If it grows
  branching logic, that logic belongs in the domain.

## Errors

- One custom error type per operation boundary, variants named for the failure.
- Recoverable failures return `Result(a, Error)`. Panics are for invariants
  that a correct program cannot violate.
- Convert external errors at the edge into domain variants; do not leak
  `Dynamic`, HTTP status codes, or driver errors into the core.
- Do not use a single giant `Error` type across unrelated features. Two small
  error types beat one `SomethingWentWrong`.

## Module ownership

- A module owns a concept, not a layer. `order` owns order types and rules;
  `order/discount` owns discount rules that `order` calls.
- Before adding a module, search for the concept: `grep -rn "pub fn " src/`, and
  run `gleam-api dupes` when you are about to add a helper that might already
  exist under another name. Extending the existing owner is cheaper and keeps
  the API discoverable.
- Public API is the module's surface: everything `pub` needs a caller or a
  test. Make helpers private.
- Avoid circular dependencies: if two modules need each other, one of them is
  holding a type that belongs in a third module.

## Guardrails: what the compiler holds, what you hold

Separate the rules a machine enforces from the ones a reviewer does, and do not
pretend the second kind is the first.

| Rule | Enforced by |
| --- | --- |
| An invalid combination cannot be built | a custom type with one variant per valid state: no other way to construct it |
| Every variant is handled | exhaustive `case` — a `_ ->` arm turns this off, silently |
| Construction goes through the module | `pub opaque type` plus constructor functions |
| A failure is not ignored | `Result(a, e)` in the signature; a caller that wants the value must match it |
| Target support | `@target(erlang)` / `@target(javascript)` plus building both |
| No IO in the domain | nothing. A test that passes a fake store or clock is the check |
| Effects only at the edge | nothing; grep imports (`grep -rn "gleam/io\|gleam/erlang" src/`) |
| One implementation per concept | `gleam-api dupes` and review |
| Domain does not import adapters | nothing; keep the import list in the reference above short and read it |

Verified compiler behaviour behind two of those rows: `let assert` on a
recoverable failure compiles and crashes at runtime, and a `_ ->` arm compiles
and hides a later variant. Both are legitimate tools; both remove a guarantee
the rest of this document relies on, so use them where you mean to.

## Abstraction budget

- No interface for one implementation.
- No option, flag, or configuration value without a caller.
- No generic helper until the second concrete use shows the shape.
- Deleting code is a valid design move: replaced paths go away in the same
  change, not behind a compatibility shim.

## Stateful boundaries

Decision order for state that outlives a call:

1. Pass it explicitly (function argument, return value). Deterministic, easy to
   test, works on both targets.
2. Hold it in a store module that the caller owns and passes in.
3. Introduce a process only when the state must be shared concurrently or must
   survive individual calls (see `otp-patterns.md`).

## Definition of done for an architecture change

- The domain rules are reachable without IO in tests.
- Public APIs are smaller or unchanged, not accidentally larger.
- Both claimed targets still build.
- No duplicate implementation of a concept that already had an owner.
