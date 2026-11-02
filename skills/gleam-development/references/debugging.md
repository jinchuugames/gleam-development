# Debugging

Load this when something is broken: a failing test, a wrong value, a crash, or
behaviour that only happens on one target.

## Two kinds of failure

| Symptom | The oracle |
| --- | --- |
| It does not compile | the compiler. Fix one error, rebuild, repeat |
| It compiles and is wrong | nothing but a test or your own reasoning |

The second kind is the one worth a procedure. `gleam build` passing proves the
types fit; it says nothing about the value, the boundary, or the state.

## The loop

1. **Reproduce it as a test before touching the code.** A failing test is the
   only proof the bug exists and the only proof the fix works. If the bug is in
   a pure rule, the test is trivial; if it needs IO, inject the dependency
   (`references/architecture.md`).
2. **Read the whole failure**, not the last line. A gleeunit assertion failure
   names the test, then the two values:

   ```
   panic src/gleeunit/should.gleam:10
    test: my_module_test.equality_failure_test
    info:
   [1, 2, 3]
   should equal
   [1, 2]
   ```

   A `let assert` failure prints the pattern, the file and line, and the value
   that did not match: `value: Error(Nil)`.
3. **Narrow before changing.** Halve the input, try the empty list, try zero,
   try the boundary twice (`n` and `n ± 1`). State the smallest input that
   fails; that sentence usually names the bug.
4. **Fix the cause once.** If the wrong branch is a shared helper, fix it where
   it lives and check the callers: `grep -rn "<function_name>" src test`.
5. **Re-run the full suite**, and both targets when the project claims two. A
   green single test is not a green project.
6. **Keep the test.** It is the regression, and it documents the rule you
   learned.

## Seeing values

```gleam
import gleam/io
import gleam/string

io.println(string.inspect(value))
```

- `gleam/io` 1.0.5 has only `print`, `println`, `print_error`,
  `println_error` — there is no `io.debug` (verified). `string.inspect` renders
  any term in Gleam syntax.
- `gleam shell` starts an Erlang REPL with the project's modules loaded, so you
  can call a function without editing a `main`:

  ```
  $ gleam shell
  1> my_module.my_function(42).
  84
  ```

  A panic in the shell prints an Erlang `gleam_error` record, so use a test
  rather than the shell when you want to read a failure.
- `let assert Ok(value) = result as "expected a parsed amount"` and
  `panic as "unreachable"` both compile and carry a message. Use them only
  where the failure really is a bug; otherwise the `Result` is the report.
- `gleam test` prints a summary line. A count lower than expected is a
  discovery problem, not a pass: `references/testing.md`.

## Bugs that compile

These classes survive the compiler. Check them explicitly when a diff "looks
right".

| Class | What it looks like | Catch it with |
| --- | --- | --- |
| Off-by-one boundary | page 1 returns the second page (`list.drop(page * size)`); a session that is still valid at its expiry second | a test at the boundary and one on each side |
| Integer precision, JavaScript target | `int.parse("9007199254740993")` gives `Ok(9007199254740993)` on the BEAM and `Ok(9007199254740992)` on JavaScript — same code, no error, measured here | run the suite on both targets; reject values above `9_007_199_254_740_991` |
| Float formatting | `float.to_string(0.000001)` is `1.0e-6` on the BEAM and `0.000001` on JavaScript; `-0.0` prints differently too (measured) | format with integers; never assert a formatted float across targets |
| Collection order | a `Dict` or `Set` iterated and compared as a list | sort before asserting; order is not a contract |
| `let assert` on a recoverable failure | a validation error becomes a crash | match the `Result`; keep `let assert` for impossible cases |
| `_ ->` in a `case` | exhaustiveness stops being checked, so a later variant is silently ignored | name every variant, or add the fallback knowingly |
| IO inside the rule | the rule cannot be tested without a database or a clock, and behaves differently per target | pass the value in; keep the effect at the edge |
| A second implementation | a helper copied under a new name instead of reused | `gleam-api dupes`, then delete the copy |

When the bug was only visible on one target, look at numbers first, then at
externals: `@external` names and paths are unchecked strings that compile and
fail at runtime on that target only (`references/beam-and-javascript.md`).

## Stop rule

Two attempts at the same symptom without new evidence: stop and write down what
you tried, what you assumed, and what would settle it. Layer a third guess on a
broken build and the diff stops being reviewable.
