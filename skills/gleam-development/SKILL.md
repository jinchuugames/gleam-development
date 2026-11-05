---
name: gleam-development
description: Use when writing, changing, debugging, or testing Gleam code (.gleam, gleam.toml, gleam_stdlib, gleeunit) — enforces API lookup before use, a compile-and-test loop, and test-discovery checks. Load this before editing any Gleam module or dependency.
---

# Gleam development

Verify unfamiliar APIs against installed sources. Use the compiler and tests to check each change.
A successful build proves that types fit. Tests check behaviour and test discovery.

The lookup script is bundled at `scripts/gleam-api`, relative to this `SKILL.md`.
Resolve its absolute path from the installed skill location.
Set `gleam_api` to that path in each shell call that uses the examples below.
Keep the current directory at the Gleam project. No PATH change is necessary.

```sh
gleam_api="/absolute/path/to/installed/gleam-development/scripts/gleam-api"
"$gleam_api" packages
```

## 1. Discovery (before writing)

Find the code that should change, and the code that already does the job.

1. Read `gleam.toml` and `manifest.toml`. Note the project name, the target,
   and the exact dependency versions. Do not assume current-release APIs.
2. Locate module ownership: `ls src/`, `grep -rn "pub fn " src/`. Match the
   module that already owns the concept.
3. **Search before writing.** Agents duplicate code they could have reused.
   Before adding a function, run all four:

   ```sh
   grep -rn "<concept>" src test      # names, doc comments, tests that mention it
   grep -rn "^pub fn " src            # existing public implementations
   "$gleam_api" dupes                    # bodies you already have under another name
   "$gleam_api" search <concept>         # installed dependencies
   ```

   `dupes` compares function bodies in `src/` and reports pairs that are mostly
   the same lines. If an equivalent exists, reuse it or extend it where it
   lives. Do not copy it into a new module. Before changing an existing
   function's signature, list its callers: `grep -rn "<function_name>" src test`.

4. Read the nearby tests for the module you are changing. They define current
   behaviour, including the cases nobody documented.
5. Decide targets: does the project build for erlang, javascript, both? Shared
   code must compile on every target the project claims (`gleam.toml`
   `target`, CI commands, existing `@target` attributes).

## 2. Verify APIs (never fabricate)

Before using an unfamiliar function or type:

```sh
"$gleam_api" sig gleam/dict.upsert     # signature, doc, package, version
"$gleam_api" find <name>               # every public symbol with that exact name
"$gleam_api" type <TypeName>           # custom type with its variants and fields
"$gleam_api" search <text>             # search names and documentation
"$gleam_api" packages                  # compiler + pinned dependency versions
```

Run the bundled script inside the project, or pass `--dir <project>`.

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
- No `_ ->` arm on a custom type: name every variant, so a new one fails the
  build instead of falling into the catch-all. `_ ->` is fine on open sets:
  strings, ints, lists.
- Keep comments short. A `////` module header says what the module owns in a
  few lines; `///` documents a public item; `//` explains a non-obvious why.
  No essays, and no history of the change: git holds that.
- Doc comments follow `references/documentation.md`: a verb-first summary,
  fixed sections, short sentences, no banned words. Run
  `scripts/gleam-doc-check src` after you change a `////` or `///` comment.
- `Result(a, e)` for recoverable failure with a custom error type; `Option(a)`
  for absence. No exceptions as control flow, no dynamic typing to dodge a
  type.
- Small public APIs, explicit types on all module functions, record labels at call
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
discovered and their count; any security-relevant surface you touched (auth, PII,
data in a public URL) and what you verified about it; remaining risks and
anything you could not verify. A diff that type-checks and passes tests can
still expose data: the compiler proves shape, not intent.
Do not claim a behaviour is correct because it compiles. When the build is
green and the value is wrong, `references/debugging.md` has the loop.

## References

| File | Load when |
| --- | --- |
| `references/idiomatic-gleam.md` | writing new modules, reviewing a diff for un-Gleam patterns |
| `references/documentation.md` | writing or changing a `////` or `///` doc comment |
| `references/stdlib-and-dependencies.md` | unsure which stdlib function or dependency version to use |
| `references/testing.md` | adding or fixing tests, or tests are not being discovered |
| `references/debugging.md` | something fails, a value is wrong, or a bug compiles and survives the build |
| `references/frontend.md` | a Lustre UI: server component or client island, drag and drop, animation, Web Components |
| `references/architecture.md` | deciding module boundaries, error types, where effects live |
| `references/otp-patterns.md` | tempted to add a process, supervisor, or shared mutable state |
| `references/beam-and-javascript.md` | dual-target code, externals, `@target`, runtime differences |
