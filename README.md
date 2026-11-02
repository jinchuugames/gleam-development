# gleam-development

An agent toolkit for Gleam: a skill that makes coding agents look up real APIs
before writing them, an `AGENTS.md` template for Gleam projects, a command-line
documentation lookup that reads the versions you actually have installed, two
architectural examples, and a benchmark harness with hidden tests.

It exists because agents invent standard-library functions in Gleam — `dict.update`
does not exist in `gleam_stdlib` 1.0.5, `dict.upsert` does. Those mistakes are
compile errors, so the fix is a loop: check the installed API, compile, test,
repair. This repository packages that loop.

## What is in here

| Path | What it is |
| --- | --- |
| `skills/gleam-development/` | The skill: `SKILL.md` plus six reference files loaded only when relevant |
| `templates/AGENTS.md` | Copyable `AGENTS.md` for a Gleam repository, with placeholders to fill |
| `scripts/gleam-api` | API lookup over installed package sources; reports package and pinned version |
| `scripts/check.sh` | Verifies formatting, examples, fixtures, lookup, and the benchmark guard |
| `examples/order-pipeline` | Pure domain: custom types, state transitions, `Result` validation, pricing |
| `examples/inventory` | Architecture: pure core, store boundary, why an actor is not justified |
| `benchmarks/` | Model-agnostic harness, six tasks, hidden tests, discovery guard |
| `docs/research.md` | What the ecosystem actually provides, verified on 2026-11-02 |

## Requirements

- Gleam 1.19.2 or newer (`gleam --version`); tested with 1.19.2.
- Erlang/OTP for the Erlang target (tested with OTP 29), Node/Deno/Bun only if
  you build for JavaScript.
- `jq` for `scripts/gleam-api --json` and the benchmark harness.

Dependencies are fetched by Gleam itself on first build; nothing here requires a
service, a model provider, or an account.

## Install

Clone, then install for the agent you use.

### Claude Code

```sh
mkdir -p ~/.claude/skills
cp -R skills/gleam-development ~/.claude/skills/
```

Skills in `~/.claude/skills/<name>/SKILL.md` are discovered at session start.
For one project only, use `.claude/skills/gleam-development/` inside that
project instead.

### omp

```sh
mkdir -p ~/.omp/agent/skills
cp -R skills/gleam-development ~/.omp/agent/skills/
```

Verified: a fresh `omp -p` session lists `gleam-development` as an available
skill after this copy (omp 18.14.2).

### Codex

Codex reads `AGENTS.md` from the repository root, so the template is the
integration:

```sh
cp templates/AGENTS.md /path/to/your-gleam-project/AGENTS.md
$EDITOR /path/to/your-gleam-project/AGENTS.md   # fill the placeholders
```

Keep the skill file in the repository as well and reference it from
`AGENTS.md` if your Codex setup supports skill files:

```sh
mkdir -p /path/to/your-gleam-project/.agents/skills
cp -R skills/gleam-development /path/to/your-gleam-project/.agents/skills/
```

### Any custom CLI agent

Give the agent the skill as system context and the lookup tool on `PATH`:

```sh
install -m 0755 scripts/gleam-api ~/.local/bin/gleam-api
```

Then start the agent with `skills/gleam-development/SKILL.md` in its system
prompt, and tell it that `gleam-api` is available. Nothing in the toolkit
assumes a particular model or harness.

## Documentation lookup

```sh
gleam-api packages                     # compiler version and pinned dependency versions
gleam-api sig gleam/dict.upsert        # exact signature, documentation, package, version
gleam-api find upsert                  # every public symbol with that name
gleam-api type Dict                    # custom type with variants
gleam-api search remove a key          # search names and documentation
gleam-api module gleam/list            # one line per public symbol
gleam-api sig gleam/dict.upsert --json # machine-readable
gleam-api find dict.update             # exits 1: it does not exist in 1.0.5
```

Run it inside the project (or pass `--dir <project>`). It reads
`build/packages/<package>/src/**/*.gleam` for dependencies and `src/` for your
own modules, and takes versions from `manifest.toml`. No network, no extra
dependency, no project mutation.

Example output on a project pinning `gleam_stdlib 1.0.5`:

```
gleam_stdlib 1.0.5  gleam/dict  (build/packages/gleam_stdlib/src/gleam/dict.gleam:446)
  pub fn upsert(in dict: Dict(k, v), update key: k, with fun: fn(Option(v)) -> v) -> Dict(k, v)
  | Creates a new dict with one entry inserted or updated using a given function.
```

### Fallback order when lookup is unavailable

1. Installed sources: `build/packages/<package>/src/**/*.gleam`, `src/**/*.gleam`.
2. Compiler interfaces: `gleam export package-interface` (current package, JSON),
   or let `gleam build` prove the call type-checks.
3. Version-pinned HexDocs: `https://hexdocs.pm/<package>/<version>/<module>.html`.

`gleamdoc` (0.4.1, maintained) is a good optional search tool, but it has to be
added as a dependency of the project being questioned, and it needs a build
first. That is why it is documented rather than required here; see
`docs/research.md`.

## Benchmark

```sh
./benchmarks/harness/run.sh                       # all tasks, conditions A-D, fixture agent
./benchmarks/harness/run.sh --tasks word-frequency
./benchmarks/harness/run.sh --self-check          # prove the discovery guard fires
./benchmarks/harness/run.sh --agent ./my-agent.sh --json results.json
```

Conditions: A baseline, B with compiler feedback, C with documentation lookup,
D with the skill. Every task has hidden tests that are injected after each
attempt and removed again, and the harness refuses a run whose tests did not
execute (`test/` placement, `gleeunit.main()` present, executed count at least
the expected number). See `benchmarks/README.md`.

The bundled agent is a fixture that replays recorded attempts. It exists so the
harness can be validated without paid API access; its scores are not evidence
about any model.

## Verified evidence

All commands below were run in this repository on 2026-11-02 with Gleam 1.19.2,
OTP 29, Node 23.11.1, `gleam_stdlib` 1.0.5, `gleeunit` 1.11.0.

- `examples/order-pipeline`: `gleam build` and `gleam test` pass, 29 tests; the
  same suite passes on `--target javascript`.
- `examples/inventory`: 28 tests pass on both `--target erlang` and
  `--target javascript`.
- `scripts/gleam-api` reports real signatures from the pinned stdlib and exits
  1 for `dict.update`.
- `benchmarks/harness/run.sh --self-check` refuses both deliberately broken
  discovery setups.
- The full fixture benchmark (6 tasks × 4 conditions): A 0/6, B 0/6 first
  attempt and 6/6 after compiler feedback, C 6/6, D 6/6. Table and failure
  modes are in `benchmarks/README.md`.
- `scripts/check.sh` passes end to end: formatting, 57 example tests, every
  task's correct attempt running its hidden tests, documentation lookup, the
  discovery guard, and the fixture benchmark.

## Limitations

- **Compilation is necessary, not sufficient.** The skill forces a test run and
  a test-discovery check, but hidden behavioural bugs can still pass. The
  benchmark exists because of this gap, not in spite of it.
- **Cross-runtime determinism is not guaranteed.** Integer precision, float
  formatting, dictionary order, and process APIs differ between Erlang and
  JavaScript. Building both targets catches compile-level differences only.
- **Architectural mistakes are reduced, not eliminated.** The references give
  decision rules (pure core, explicit state, actors only when justified); they
  are not proofs.
- **Version awareness depends on the project being built.** `gleam-api` reads
  what the compiler downloaded. Before a first build there is nothing to read,
  and it says so rather than guessing.
- **The benchmark is small.** Six tasks with a fixture agent validate the
  harness. A run against a real agent is one sample; do not read statistical
  significance into it.
- **The skill is per-agent.** Each agent has its own skill or instruction
  mechanism; this repository provides the content and the install commands, not
  a universal plugin.

## Adding a task or changing the skill

- Keep `SKILL.md` short; put detail in `references/` so it loads only when the
  topic comes up.
- A benchmark task needs a `work/` project, hidden tests with
  `visible_tests`/`hidden_tests` counts in `meta.json`, and recorded attempts
  for `baseline`, `docs`, and `feedback`.
- Run `scripts/check.sh` before claiming anything works. It formats, builds,
  tests, checks lookup, and runs the benchmark guard.

## Research and prior art

`docs/research.md` records what was verified: the compiler and its subcommands,
the language server, HexDocs version pinning, `gleamdoc`'s real status, existing
Gleam agent skills and MCP servers, gleeunit's discovery behaviour, formatting,
and both targets. Two Curling IO experience reports are cited there as
author opinion: agents duplicate code they could reuse, and Gleam's compile
loop is what makes agent iteration work.
