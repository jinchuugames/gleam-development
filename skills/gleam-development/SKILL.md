---
name: gleam-development
description: Use when writing, changing, debugging, or testing Gleam code (.gleam, gleam.toml, gleam_stdlib, gleeunit) — enforces API lookup before use, a compile-and-test loop, and test-discovery checks. Load this before editing any Gleam module or dependency.
---

# Gleam development

Gleam has less training data than Go, Rust, TypeScript, or Elixir, so the
first attempt usually contains something that does not exist: an invented
standard-library function, a missing import, a type mismatch. Every one of
those is a compile error, and the compiler is fast. Use it as the feedback
loop, and verify APIs against installed sources instead of memory.

## 1. Discovery (before writing)

Find the code that should change, and the code that already does the job.

1. Read `gleam.toml` and `manifest.toml`. Note the project name, the target,
   and the exact dependency versions. Do not assume current-release APIs.
2. Locate module ownership: `ls src/`, `grep -rn "pub fn " src/`. Match the
   module that already owns the concept.
3. **Search before writing.** Agents duplicate code they could have reused.
   Before adding a function, run all three:

   ```sh
   grep -rn "<concept>" src test      # names, doc comments, tests that mention it
   grep -rn "^pub fn " src            # existing public implementations
   gleam-api search <concept>         # installed dependencies
   ```

   If an equivalent exists, reuse it or extend it where it lives. Do not copy
   it into a new module. Before changing an existing function's signature, list
   its callers: `grep -rn "<function_name>" src test`.

4. Read the nearby tests for the module you are changing. They define current
   behaviour, including the cases nobody documented.
5. Decide targets: does the project build for erlang, javascript, both? Shared
   code must compile on every target the project claims (`gleam.toml`
   `target`, CI commands, existing `@target` attributes).

## 2. Verify APIs (never fabricate)

Before using an unfamiliar function or type:

```sh
gleam-api sig gleam/dict.upsert     # signature, doc, package, version
gleam-api find <name>               # every public symbol with that exact name
gleam-api type <TypeName>           # custom type with its variants and fields
gleam-api search <text>             # search names and documentation
gleam-api packages                  # compiler + pinned dependency versions
```

`gleam-api` lives in this toolkit's `scripts/` and must be run from (or
pointed at) the project with `--dir <project>`.

If `gleam-api` is unavailable, use this fallback order, and say which step you
used:

1. Installed sources: `build/packages/<package>/src/**/*.gleam` and `src/**/*.gleam`.
   `grep -rn "^pub fn <name>" build/packages/*/src` is usually enough.
2. Compiler interfaces: `gleam export package-interface` (current package, JSON),
   or let `gleam build` decide whether the call type-checks.
3. Published docs, version-pinned: `https://hexdocs.pm/<package>/<version>/<module>.html`
   (for example `gleam_stdlib/1.0.5/gleam/dict.html`). Never the unversioned
   page when the project pins an older release.

If none of them contains the symbol, **it does not exist**. Do not invent it,
do not guess a plausible name, and do not write code that "should" compile.

Known verified example: `gleam_stdlib` 1.0.5 has no `dict.update`; the
equivalent is `dict.upsert(dict, key, fn(Option(v)) -> v)`. Do not extend this
list from memory — check each name you are about to write.

## 3. Write idiomatic Gleam

- Pure functions first; push effects to the edges.
- Custom types plus exhaustive `case` instead of strings, maps, or booleans to
  encode state.
- `Result(a, e)` for recoverable failure with a custom error type; `Option(a)`
  for absence. No exceptions as control flow, no dynamic typing to dodge a
  type.
- Small public APIs, explicit types on public functions, record labels at call
  sites when a call has more than one argument of the same type.
- No new OTP process unless there is a real reason (shared mutable state,
  supervision, timing). An ordinary module with explicit state passed in is
  the default.
- Preserve unrelated behaviour. Change only what the task asks for.

Details: `references/idiomatic-gleam.md`, `references/architecture.md`,
`references/otp-patterns.md`.

## 4. Compile-and-test loop (mandatory)

```sh
gleam format src test          # canonical formatting, no configuration
gleam build                    # or: gleam check
gleam test                     # runs main() of <project>_test
gleam build --target javascript && gleam test --target javascript   # if shared
```

After each change that could break compilation, rebuild before writing more
code. Repair compiler errors one at a time; do not continue layering changes on
a broken build. Treat warnings as signals too: `gleam build --warnings-as-errors`
in CI.

**Confirm the tests actually ran.** `gleam test` only invokes the entry module
`<project>_test`; `gleeunit.main()` then scans `test/**/*.gleam` for `_test`
functions. So:

- test files must live under `test/` (not `src/`, not a sibling directory);
- the entry module must still call `gleeunit.main()`;
- the summary line must report at least the number of tests you expect.

"No tests found!" or a suspiciously low pass count is a failure to investigate,
not a pass. Never delete, skip, or weaken a failing test to get green.

Details: `references/testing.md`.

## 5. Finish

Report: behaviour implemented or preserved; modules changed; public API
changes; commands run with results (`build`, `test`, both targets); tests
discovered and their count; remaining risks and anything you could not verify.
Do not claim a behaviour is correct because it compiles.

## References

| File | Load when |
| --- | --- |
| `references/idiomatic-gleam.md` | writing new modules, reviewing a diff for un-Gleam patterns |
| `references/stdlib-and-dependencies.md` | unsure which stdlib function or dependency version to use |
| `references/testing.md` | adding or fixing tests, or tests are not being discovered |
| `references/architecture.md` | deciding module boundaries, error types, where effects live |
| `references/otp-patterns.md` | tempted to add a process, supervisor, or shared mutable state |
| `references/beam-and-javascript.md` | dual-target code, externals, `@target`, runtime differences |
