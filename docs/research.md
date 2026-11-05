# Research: what an agent can rely on when writing Gleam

Every claim below was checked on this machine on 2026-11-02 unless marked
otherwise. Versions observed: `gleam 1.19.2`, Erlang/OTP 29, Node v23.11.1,
`gleam_stdlib 1.0.5`, `gleeunit 1.11.0`, `gleamdoc 0.4.1`.

Legend: **verified** means a command was run here and its output is quoted or
summarised; **unverified** means it is taken from documentation or another
source without a local check.

## Summary

| Tool | Maintained | Current releases | Works locally | Needs network | Agent-suitable as-is | Compiler/LSP already does it? |
| --- | --- | --- | --- | --- | --- | --- |
| `gleam` compiler + CLI | Yes | 1.19.2 (verified) | Yes | Only to fetch deps | Yes — best feedback loop available | n/a |
| `gleam lsp` | Yes (part of compiler) | 1.19.2 | Yes | Only to fetch deps | No — needs a JSON-RPC client | Duplicates compiler diagnostics, adds hover/definition |
| Installed package sources (`build/packages/<pkg>/src`) | Yes (produced by compiler) | Whatever is pinned | Yes | No | Yes | No — this is the only offline source of truth for dependency APIs |
| `gleam export package-interface` | Yes (part of compiler) | 1.19.2 | Yes | No | Yes, but own package only | Partly — machine-readable interfaces for the project itself |
| HexDocs | Yes | Version-pinned URLs work | No | Yes | Yes, with a network | No — authoritative published docs, not local |
| `gleamdoc` | Yes, small project | 0.4.1 (2026-10-11) | Yes, but must be added to the target project | Yes, to install | Conditional | Uses the same compiler interfaces, adds search/JSON |
| Existing Gleam agent skills | Partly | n/a | n/a | n/a | Partly | None combine doc lookup with a compile loop |
| Gleam MCP servers | Only builder libraries | n/a | n/a | n/a | No (no code-intelligence server found) | n/a |
| `gleeunit` | Yes | 1.11.0 | Yes | No | Yes, with a discovery caveat | No |
| `gleam format` | Yes | 1.19.2 | Yes | No | Yes | n/a |
| Erlang target | Yes (OTP 29) | n/a | Yes | No | Yes | n/a |
| JavaScript target | Yes (Node 23) | n/a | Yes | No | Yes | n/a |

## Compiler and CLI — verified

`gleam --version` → `gleam 1.19.2`. Relevant subcommands, all confirmed with
`--help` and by running them:

- `gleam check [-t erlang|javascript]` — type check without producing a build.
- `gleam build [-t erlang|javascript] [--warnings-as-errors]` — full build.
- `gleam test [-t erlang|javascript] [--runtime nodejs|deno|bun]` — runs the
  `main` function of the `<PROJECT_NAME>_test` module.
- `gleam format [--check]` — canonical formatting, no configuration.
- `gleam docs build` — renders HTML into `build/dev/docs/<package>/`.
- `gleam export package-interface [--out PATH]` — JSON of the current
  package's public modules, functions, types, and per-target capability flags.
- `gleam lsp` — language server over stdio.
- `gleam deps download`, `gleam deps list`, `gleam add`, `gleam remove`,
  `gleam update`, `gleam fix`, `gleam shell`.

`gleam build` is fast: `Compiled in 0.27s` for a fresh two-dependency project,
`0.16s` for an incremental check. That speed is what makes a compile-first
agent loop affordable.

**Duplicate check:** nothing else in the ecosystem is needed to detect type
errors, missing imports, exhaustiveness, or target mismatches. The compiler is
the arbiter; the toolkit does not wrap it.

## Installed package sources — verified

After `gleam build`, the compiler writes each dependency's source into
`build/packages/<package>/src/`, e.g.
`build/packages/gleam_stdlib/src/gleam/dict.gleam`. These files are the exact
source of the pinned version and are readable offline. `manifest.toml` pins
`gleam_stdlib 1.0.5`, `gleeunit 1.11.0` for the probe project.

This is the cheapest reliable API oracle for an agent: `grep`/`awk` over those
files answers "does `dict.update` exist" in milliseconds with no network, no
extra dependency, and no project mutation. `scripts/gleam-api` is built on it.

## `gleam export package-interface` — verified

Prints JSON for the **current package only**; a probe project's dependencies
were not included. Each function carries `parameters`, `return`, and
`implementations` with `can-run-on-erlang` / `can-run-on-javascript` /
`gleam` / `uses-*-externals`. Useful for per-target facts about your own
modules; not a dependency documentation source.

## Language server — verified

`gleam lsp` speaks JSON-RPC over stdio. A minimal `initialize` handshake
returned:

```
capabilities: codeActionProvider, completionProvider, definitionProvider,
documentFormattingProvider, documentHighlightProvider, documentSymbolProvider,
foldingRangeProvider, hoverProvider, referencesProvider, renameProvider,
signatureHelpProvider, textDocumentSync, typeDefinitionProvider, workspace
```

It also emitted a `window/workDoneProgress/create` progress token while
downloading dependencies, and `shutdown` + `exit` completed cleanly.

**Verdict:** maintained, current, local, and the best hover/definition source —
but a plain shell-driven agent cannot use it without a JSON-RPC client. The
toolkit therefore treats it as *available to editors and clients that already
speak LSP*, not as a dependency. Do not build a custom LSP client for this.

## HexDocs — verified

`https://hexdocs.pm/gleam_stdlib/1.0.5/gleam/dict.html` returns a 301 to
`https://gleam-stdlib.hexdocs.pm/1.0.5/gleam/dict.html`, and that page contains
`upsert` for the pinned version. Version-pinned URLs are therefore usable, but
they require a network and are not local: last resort, after installed sources
and compiler interfaces.

Collision to watch: `hexdocs.pm/gleam_stdlib` and the unversioned URL serve the
current release, not the pinned one. An agent that quotes unversioned HexDocs
can confirm a function that does not exist in the project's locked version.

## `gleamdoc` — verified, conditional

- Latest release **0.4.1**, published 2026-10-11 (Hex API). The earlier
  releases are 0.4.0 (2026-08-12), 0.3.0 (2026-07-17), and 0.2.0 (2026-06-23).
  All-time downloads 348. Small, active, single maintainer
  (`~jturner/gleamdoc` on sourcehut).
- Not on this machine's `PATH`. It is a Gleam package, not a system binary, and
  it declares no `escript`, so `gleam export escript` cannot produce a
  standalone binary from it as published.
- Running it requires `gleam add gleamdoc` **inside the project being
  queried**, because it reads that project's compiler-generated package
  interfaces:

  ```
  gleam run -m gleamdoc -- index       # index the project + local deps
  gleam run -m gleamdoc -- packages    # package list with versions
  gleam run -m gleamdoc -- search "dict update" --json=TRUE
  ```

  Verified output includes `gleam_stdlib:gleam/dict.upsert` with a fully
  qualified signature and documentation, and JSON records with
  `package`, `version`, `module`, `kind`, `name`, `signature`, `documentation`.

**Why it is not the toolkit's primary path:** adding a dependency to somebody
else's project in order to ask a question about that project is an invasive
default, and it needs network access the first time. Its qualified signatures
are precise but noisy for prompt context. It is documented here and in
`skills/gleam-development/references/stdlib-and-dependencies.md` as an optional
upgrade for projects that already depend on it; the toolkit's `scripts/gleam-api`
reproduces the useful subset (find, search, signature, type, package+version,
JSON) from sources already on disk.

## Existing Gleam agent skills and MCP servers — verified

- `gleamdev/claude-plugins` — a Claude Code plugin marketplace for *Gleam the
  product* (`app.gleamdev.com`), not the language; its skills directory is an
  empty placeholder. Not relevant.
- `TheBushidoCollective/han` → `plugins/languages/gleam` — three skills (actor
  model, interop, type system) plus hooks, installed via a plugin CLI. Relevant
  prior art; none of them performs dependency API lookup or enforces a
  compile-and-test loop, which is the gap this toolkit fills.
- `aide` (0.7.1) and `mcp_toolkit` (0.3.1) are libraries for **building** MCP
  servers in Gleam. Neither is a Gleam code-intelligence MCP server, and no
  such server was found. An MCP server would also require a client that speaks
  MCP, so it fails the "works with a custom CLI agent" constraint.

**Verdict:** there is no maintained, offline, agent-callable Gleam API lookup
that works from a plain shell, so a thin script is justified. It is ~200 lines
of shell over the compiler's own downloaded sources, not a new search engine.

## `gleeunit` and test discovery — verified, with a trap

`gleeunit 1.11.0`. `gleeunit.main()` finds `test/**/*.{erl,gleam}`, converts
paths to Erlang module names, and runs every `_test` function through EUnit; a
panicking test is a failure. Verified behaviour:

- A failing test in `test/extra_test.gleam` that nothing imports **was**
  discovered and made `gleam test` exit 1, on both the Erlang and JavaScript
  targets.
- `gleam test --help` states it runs `main` from `<PROJECT_NAME>_test`. So a
  test file outside `test/` is never compiled as a test, and a test entry
  module that does not call `gleeunit.main()` silently runs nothing. Both are
  false passes, and both are exactly the trap the benchmark harness must
  detect.

Therefore the benchmark guard checks three things and refuses the run when any
fails: the fixture test file is present under `test/`, the entry module still
calls `gleeunit.main`, and the reported number of executed tests is at least
the number the harness injected. A deliberate canary run proves the guard
fires.

## Formatting and static analysis — verified

`gleam format --check` is canonical and has no configuration; `gleam build
--warnings-as-errors` promotes warnings to failures. There is no separate
linter in the core toolchain. Both are wired into the skill's loop.

## Targets — verified

- Erlang: `gleam test` runs under OTP 29; exit status 1 on failure.
- JavaScript: `gleam test --target javascript` runs the same suite under Node
  23; exit status 1 on failure; `--runtime deno|bun` selects another runtime.
- Target capability flags per function are available from
  `gleam export package-interface` for the local package; dependency target
  support is proved by building both targets rather than by guessing.

## Cross-target numeric behaviour — verified

Measured with one module run on both targets (`gleam run` and
`gleam run --target javascript`, gleam 1.19.2, OTP 29, Node 23.11.1):

| Expression | Erlang | JavaScript |
| --- | --- | --- |
| `int.parse("9007199254740993")` | `Ok(9007199254740993)` | `Ok(9007199254740992)` |
| literal `9_007_199_254_740_993` | `9007199254740993` | `9007199254740992` |
| `9_007_199_254_740_992 + 1` | `9007199254740993` | `9007199254740992` |
| `float.to_string(0.000001)` | `1.0e-6` | `0.000001` |
| `float.to_string(-0.0)` | `-0.0` | `0.0` |

Both targets compile the same source without a warning. The JavaScript target
still returns `Ok` for a value it cannot hold. `9_007_199_254_740_991`
(`2^53 - 1`) is the largest integer both targets represent exactly. Everything
else in the float probe (`12.05`, `0.1 +. 0.2`, `1.0e21`, `100.0 /. 3.0`)
printed identically, so exponent notation for small values and negative zero are
the observed formatting differences, not a general wildcard.

## Language surface facts — verified

- Gleam has no `if` expression and no grouping parentheses around an expression
  (`(a <> b)`); the compiler suggests a `case` and `{}` respectively.
- `<`, `>` and `<=` are `Int` only: comparing two strings is a type error and
  the fix is `string.compare(a, b) -> order.Order`.
- A custom type named `Error` declares variants, not a constructor named
  `Error`; `Error(x)` in a `Result` is the `Result` constructor.
- `gleam/io` 1.0.5 exposes `print`, `print_error`, `println`, `println_error`
  only. There is no `io.debug`. `string.inspect(term)` renders any value.
- `let assert Ok(value) = result as "message"` and `panic as "message"` compile
  and carry the message into the failure.
- `gleam shell` starts an Erlang REPL with the project's modules loaded: for a
  probe module defining `double(n: Int) -> Int`, `intprobe:double(21).` returned
  `42`.

## Lustre 5.7.1 — verified

Pinned in a probe project (`gleam add lustre` → `lustre 5.7.1`, with `houdini
1.2.1`), built for both targets, and read through `scripts/gleam-api`:

- `lustre/server_component`: `element`, `script`, `route`, `method`
  (`TransportMethod = WebSocket | ServerSentEvents | Polling`), `include`,
  `csrf_token`, `emit`, `select`, `subject`, `pid`, `register_subject`.
- `lustre/component`: `open_shadow_root`, `adopt_styles`, `delegates_focus`,
  `form_associated`, `part`, `parts`, `exportparts`, `slot`, `default_slot`,
  `named_slot`, `prerender`, `on_attribute_change`, `on_property_change`.
- `lustre/runtime/app.default_config` has `open_shadow_root: True` and
  `adopt_styles: True`.
- `lustre/event` has click, mouse, keyboard, input, change, check, submit,
  focus, blur and the generic `on(name, decoder)`. It has **no** drag-and-drop
  event helpers. There is no helper for animating DOM state either; the only
  animation-shaped symbols in the package are SVG SMIL elements in
  `lustre/element/svg` (`animate`, `animate_motion`, `animate_transform`).
- `lustre/dev/simulate`: `simple`, `application`, `start`, `message`, `click`,
  `input`, `submit`, `event`, `model`, `view`, `history`. A drag state machine
  written with it ran green on both targets: `3 passed, no failures` on
  `gleam test` and on `gleam test --target javascript`.

## `gleam-api dupes` — verified behaviour

The duplicate report is a Dice coefficient over normalized body lines of the
project's own `src/` functions, minimum five lines per body, threshold 0.6.
Calibration on this machine: 0 pairs across `examples/inventory` (16 functions)
and `examples/order-pipeline` (17), 1 pair across the 729 top-level functions of
`lustre 5.7.1`'s own source (two five-line JSON builders that differ by one
line), and 1 pair for a seeded copy scoring 0.80. Masking identifiers before
comparing was tried and rejected: it made every four-line wrapper in
`lustre/attribute` look identical, which is noise rather than a finding.

## Research inputs from the field

Two articles by Curling IO were supplied as research input. They are author
experience reports, not measurements, and are treated as such.

- *AI Agents Love Gleam* (`curling.io/blog/21-reasons-ai-agents-love-gleam`,
  opinion/report). Supports the compile-first loop: the author calls the
  compile-fix cycle "the whole game" and says agents write worse Gleam on the
  first attempt because there is less training data, reaching for patterns and
  functions that do not exist. It also reports that agents **duplicate code
  rather than reuse existing functions**, probably because of context limits,
  and that catching those reuse opportunities was their most common review
  feedback. This is why the skill's discovery step gives concrete search
  commands over the project, its tests, and installed dependencies instead of
  saying "look for existing code".
- *Why We Chose Rust for Version 3*
  (`curling.io/blog/why-we-chose-rust-for-version-3`, opinion/report). The move
  away from Gleam is attributed to deployment and ecosystem fit — packaging a
  SQLite NIF for an Erlang release, and barely using BEAM-specific behaviour —
  not to agents producing worse Gleam. The same article says agents benefited
  from Gleam's static types, explicit optionals, and exhaustive matching, and
  that Gleam code was still preferable to read and write. The toolkit
  therefore does not use this article as evidence against Gleam, and it does
  not present the toolkit as a reason to choose Gleam.

## Documentation fallback order (implemented)

1. **Installed package sources** — `build/packages/<pkg>/src/**.gleam` for
   dependencies and `src/**.gleam` for the project. Exact pinned code,
   offline, no setup. `scripts/gleam-api` reads these.
2. **Compiler-generated interfaces** — `gleam export package-interface` for the
   project's own modules; `gleam check`/`gleam build` for anything the compiler
   can answer (existence, arity, types, exhaustiveness, target support).
3. **Authoritative published docs** — version-pinned HexDocs
   (`https://hexdocs.pm/<package>/<version>/<module>.html`), and optionally
   `gleamdoc` if the project already has it. Never the unversioned docs page
   when the project pins an older release.

Anything not found in those three has to be treated as nonexistent until the
compiler proves otherwise.
