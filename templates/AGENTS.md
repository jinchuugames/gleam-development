<!--
AGENTS.md template for a Gleam repository.

Copy this file to the repository root as AGENTS.md and replace every
<PLACEHOLDER>. This template is under about 90 lines including this comment;
keep it in that range, because it is loaded into every agent session and should
hold only what an agent cannot discover in one or two commands. The detailed workflow lives in the gleam-development skill; do not
paste that skill here.
-->

# <PROJECT NAME>

<One sentence: what this project does and for whom.>

## Architecture

- `<src/app.gleam>` — application entry and wiring; the only impure layer.
- `<src/domain/>` — pure domain types and rules. No IO, time, or randomness.
- `<src/adapters/>` — <database, HTTP client, message queue> boundaries.
- `<test/>` — gleeunit tests; files here are discovered automatically.

Module ownership: <e.g. "anything about orders lives in `src/order*`; do not add
a second order module">.

## Versions

- Gleam: `<1.19.2>` (pinned in `<.tool-versions>` / CI).
- Dependencies are pinned by `manifest.toml`; commit it and do not edit it.
- Add a dependency only with a stated reason. Do not upgrade dependencies as
  part of an unrelated change.

## Commands

```sh
gleam format src test
gleam build
gleam test
gleam test --target javascript   # only if this project supports it
```

Definition of done: formatting clean, build green, tests green, test count
unchanged or higher, no unrelated files touched.

## API lookup

Use the installed `gleam-development` skill to verify unfamiliar APIs.
Its bundled `scripts/gleam-api` resolves from the skill directory and needs no PATH change.
Check existing project code before you add a helper.

If the skill is unavailable, read
`build/packages/<package>/src/**/*.gleam`, then `gleam export
package-interface`, then version-pinned HexDocs
(`https://hexdocs.pm/<package>/<version>/<module>.html`). If a symbol is in none
of them, it does not exist in this project.

## Targets

<Erlang only | Erlang and JavaScript.> Shared modules must not import
`gleam_erlang` or `gleam_otp` when JavaScript is supported; gate target-specific
modules with `@target(erlang)` / `@target(javascript)`.

## Conventions

- Pure functions first; effects at the edges.
- Custom types plus exhaustive `case` for state; no stringly-typed status.
- `Result(a, CustomError)` for recoverable failure; panics only for impossible
  states.
- Public APIs stay small; helpers are private.
- No duplicate implementation of an existing function: search `src/` before
  writing one.
- No unrelated refactors, renames, or dependency changes in a task branch.

## Tests

- `gleam test` runs `<PROJECT>_test`; it must call `gleeunit.main()`.
- Test files belong in `test/`. A file elsewhere never runs.
- Confirm the summary line reports the number of tests you expect.
- Behaviour is the assertion target, not implementation detail.
- A bug fix includes a test that failed before it.
