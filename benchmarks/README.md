# Benchmark

A model-agnostic harness that measures whether an agent writes correct Gleam,
with and without the toolkit. It never imports a provider SDK and needs no paid
API access for its own validation: a fixture agent replays recorded attempts so
the infrastructure can be exercised offline.

**What it measures:** whether hidden tests pass. **What it does not measure:**
model quality when run with the fixture agent. Fixture results validate the
harness; only a real agent run is evidence about an agent.

## Conditions

| Condition | Compiler feedback | API lookup | Skill |
| --- | --- | --- | --- |
| A baseline | no | no | no |
| B + compiler feedback | yes | no | no |
| C + documentation lookup | yes | yes (`scripts/gleam-api`) | no |
| D + skill | yes | yes | `skills/gleam-development/SKILL.md` |

A gets one attempt and never sees compiler output. B, C, and D get up to
`--max-attempts` (default 3) attempts, each followed by `gleam build` and the
visible tests; the failure output is written to the agent's feedback file.
Hidden tests are injected only after an attempt finishes, then removed.

## Tasks

| Task | Covers |
| --- | --- |
| `word-frequency` | standard-library API verification, dict and list transformations |
| `cart-totals` | custom types, exhaustive pattern matching, integer discount rules |
| `validate-user` | `Result`-based validation, error variants, trimming |
| `reuse-format` | multi-module change, reuse of an existing implementation, duplicate detection |
| `target-split` | Erlang/JavaScript target compatibility, `@target` gating |
| `bugfix-pagination` | bug fix that compiles but is wrong on a boundary |

Every task has a `work/` project, a `prompt.md`, hidden tests in `hidden/`, and
recorded attempts in `agent/`. A task's hidden tests are never present in the
agent's work directory.

## Layout of a task

```
tasks/<id>/
  meta.json        targets, hidden module name, test counts, expected files, forbidden duplicates
  prompt.md        what the agent is told
  work/            the project handed to the agent (gleam.toml, manifest.toml, src/, test/)
  hidden/zz_hidden_test.gleam
  agent/baseline/  recorded first attempt, blind (used by B; A stops here)
  agent/docs/      recorded first attempt with API lookup (used by C and D)
  agent/feedback/  recorded partial repair after compiler/test output; still defective
  agent/repair/    recorded remaining fix (used on attempt 3)
```

Each `agent/<variant>/` directory contains only the files that variant changes,
at the same relative paths as in `work/`.

Which variant is replayed:

| Condition | Attempt 1 | Attempt 2 | Attempt 3 |
| --- | --- | --- | --- |
| A | baseline | — | — |
| B | baseline | feedback | repair |
| C | docs | feedback | repair |
| D | docs | feedback | repair |

So B's evidence is a distinct partial repair applied from feedback, not the same
file C reaches first. Two tasks (`validate-user`, `bugfix-pagination`) start
from a seeded stub or bug, so their `baseline` attempt modifies nothing; the
other four replay a recorded failed attempt that changes the source.

## Agent contract

Any executable works as an agent:

- invoked with the task work directory as its working directory;
- the task prompt is in `$BENCH_PROMPT_FILE`;
- environment: `BENCH_TASK`, `BENCH_CONDITION`, `BENCH_ATTEMPT`,
  `BENCH_VARIANT`, `BENCH_FEEDBACK_FILE` (compiler output from the previous
  attempt), `BENCH_METRICS` (write a JSON file here), and only when the
  condition allows it, `BENCH_DOCS_CMD` (C and D) and `BENCH_SKILL_FILE` (D);
- the toolkit is staged under `$out/.stage/`, so no path in its environment
  reaches the repository or `benchmarks/tasks/*/hidden/`;
- it edits files in the work directory and exits;
- it is killed after `BENCH_AGENT_TIMEOUT` seconds (default 600) and the
  attempt is recorded as failed.

`BENCH_METRICS` is optional and should contain
`{"files_read": Int, "tokens": Int|null, "model": String}`. Tokens are reported
only when the agent's provider exposes them; the fixture agent writes `null`
because no model was involved. Metrics the provider does not expose stay null —
the harness does not invent numbers.

## Metrics

`results.json` records, per task and condition:

- `first_attempt_pass`, `final_pass`
- `attempts`, `compiler_iterations` (builds run), `test_iterations`
- `wall_clock_seconds`
- `files_read` (agent-reported), `files_modified`, `unrelated_changes`
- `duplicated_implementations` (forbidden symbols found in `src/`)
- `behavioural_regression` (visible tests failing after the change)

## Test-discovery guard

A green run is only accepted when the tests actually executed. For every
attempt the harness:

1. copies the hidden test into `test/`;
2. refuses the run with `DISCOVERY FAILURE ...` when the file is not there,
   when `test/<project>_test.gleam` no longer calls `gleeunit.main()`, when
   gleeunit reports `No tests found!`, or when the hidden run executes fewer
   than `hidden_tests` more tests than the visible run did — a delta, so adding
   passing tests of your own does not satisfy the guard;
3. removes the hidden file again so the next attempt cannot see it.

Prove the guard works:

```sh
./benchmarks/harness/run.sh --self-check
```

It probes each condition's environment (A must receive no toolkit path, C the
lookup command only, D both, and no path may contain the repository root),
breaks discovery in three ways (hidden test outside `test/`, an entry module
that stops calling `gleeunit.main()`, and a hollow hidden test that adds one
trivial pass instead of the expected tests), and checks that a hanging agent is
recorded as a timeout. It fails unless every check holds.

## Running

```sh
./benchmarks/harness/run.sh                          # all tasks, all conditions, fixture agent
./benchmarks/harness/run.sh --tasks word-frequency   # one task
./benchmarks/harness/run.sh --conditions A,C         # chosen conditions
./benchmarks/harness/run.sh --agent ./my-agent.sh --json results.json
```

Output goes to `/tmp/gleam-bench` by default (`--out` to change). An `--out`
inside the repository is refused, because the staged toolkit and the prompt
files are handed to the agent and must not lead back to the hidden tests.

`BENCH_AGENT_TIMEOUT` (default 600) bounds each agent attempt with `timeout` or
`gtimeout`; when neither binary exists the harness prints a warning and runs
unbounded. `BENCH_TIMEOUT_BIN` overrides the binary, and setting it empty
disables the bound.

A real agent adapter is a thin wrapper that passes the prompt to the model,
applies its edits to the current directory, and writes `$BENCH_METRICS`. Keep it
outside this repository if it needs credentials; nothing here should contain
one.

## Fixture results on this machine

Measured 2026-11-02, Gleam 1.19.2, OTP 29, Node 23.11.1, `gleam_stdlib` 1.0.5,
`gleeunit` 1.11.0, fixture agent, 6 tasks × 4 conditions (24 runs):

| Task | A final | B first → final | C first → final | D first → final |
| --- | --- | --- | --- | --- |
| `word-frequency` | fail | fail → pass (3 attempts) | pass | pass |
| `cart-totals` | fail | fail → pass (3 attempts) | pass | pass |
| `validate-user` | fail | fail → pass (3 attempts) | pass | pass |
| `reuse-format` | fail | fail → pass (3 attempts) | pass | pass |
| `target-split` | fail | fail → pass (3 attempts) | pass | pass |
| `bugfix-pagination` | fail | fail → pass (3 attempts) | pass | pass |
| **totals** | **0/6** | **0/6 → 6/6** | **6/6** | **6/6** |

Every B run takes three attempts: the first fails, the recorded repair still
fails the acceptance tests, and the final correction passes. That is the
compiler-feedback cycle, not a single correct file replayed.

The failures are the ones the recorded attempts encode: an invented
`dict.update`, a missing `Fixed` match arm, a stub that returns `Ok`
unconditionally, a duplicated truncation helper with an off-by-one, a
hardcoded Erlang origin, and a 1-based pagination bug. The second B attempt
fixes only the reported problem (compile error, failed assertion) and leaves a
remaining defect, which is why it still fails. A/B/C/D distinguish recorded
attempts; they are not a measured improvement from the toolkit, because no
model was involved.

## Nondeterminism and honesty

- Model sampling, network latency, and machine load vary between runs. A
  handful of runs is an anecdote, not a result: report counts, not percentages
  of significance.
- Dependency downloads need network on the first build of a task.
- The recorded attempts are fixed, so fixture scores are deterministic and say
  nothing about any model. Which variant is replayed is chosen by condition, so
  the fixture table shows the harness distinguishing A/B/C/D, not a measured
  improvement from the toolkit. In the bundled fixtures, D replays the same
  recorded attempt as C, so C and D scores are identical by construction.
- `hidden_tests` and `visible_tests` in `meta.json` are the guard's
  expectations; keep them correct when editing a task, or the guard will refuse
  honest runs.
