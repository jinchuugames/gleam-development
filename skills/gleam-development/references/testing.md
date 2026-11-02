# Testing

Load this when adding tests, fixing a failing test, or when a test run looks
too good to be true.

## Discovery: the failure mode to check first

`gleam test` runs `main` from the entry module `<project>_test`. With gleeunit,
that `main` calls `gleeunit.main()`, which scans `test/**/*.{gleam,erl}` and
runs every function whose name ends in `_test`.

Consequences, all verified:

- A test file under `test/` is discovered automatically; it does not need to be
  imported by the entry module.
- A test file outside `test/` (for example `src/foo_test.gleam`) is never run.
- If the entry module stops calling `gleeunit.main()`, `gleam test` still exits
  0 and no tests run.

So after running tests, read the summary line:

```
3 passed, no failures
```

If the count is lower than the number of `_test` functions you expect, or you
see `No tests found!`, treat the run as failed and find out why. Never "fix" a
red test by deleting it, renaming it out of discovery, or weakening its
assertion.

## Layout

```
test/
  <project>_test.gleam     # entry: pub fn main() { gleeunit.main() }
  <module>_test.gleam      # one per module is a good default
```

```gleam
// test/order_test.gleam
import gleeunit/should
import order_pipeline

pub fn empty_cart_is_rejected_test() {
  order_pipeline.validate([])
  |> should.be_error()
  |> should.equal(order_pipeline.EmptyCart)
}
```

Use `gleeunit/should` (`equal`, `not_equal`, `be_ok`, `be_error`, `be_some`,
`be_none`, `be_true`, `be_false`, `fail`) or plain `assert`. Both fail the test
on mismatch; `should` reads better in tables of cases.

## What a useful test asserts

- Behaviour, not implementation: the returned value, the `Result` variant, the
  state after a transition.
- Every branch of a `case` over a custom type, especially the rejection branch.
- The boundary of a range: zero, empty list, max, one element.
- One end-to-end sequence through the public API, so the modules are proven to
  fit together.
- A regression test when fixing a bug: fail before the fix, pass after.

Avoid: asserting that a function does not crash, snapshotting a formatted
string that nobody depends on, or testing a private helper through a public
wrapper when the helper's contract is already covered.

## Determinism

- No wall-clock, network, or randomness in tests without injection. Pass the
  clock or a seeded value in.
- Dictionary and set iteration order is not guaranteed; sort before asserting
  when order is irrelevant.
- Do not depend on tests running in a particular order; gleeunit runs them all.
- `ScaleTimeouts(10)` is applied by gleeunit, so a slow CI box does not turn a
  correct test red.

## Both targets

When the project claims JavaScript support:

```sh
gleam test                            # erlang
gleam test --target javascript        # node by default; --runtime deno|bun
```

A test that passes on one target and fails on the other usually means a
target-specific external, a float/string formatting difference, or a process
API that does not exist in JavaScript. Fix the shared code, not the test.
