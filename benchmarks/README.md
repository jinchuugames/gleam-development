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
  agent/baseline/  recorded first attempt (files copied over work/)
  agent/docs/      recorded first attempt with API lookup (used by C and D)
  agent/feedback/  recorded repair after compiler output (used by B, C, D on attempt 2+)
```

Each `agent/<variant>/` directory contains only the files that variant changes,
at the same relative paths as in `work/`.

## Agent contract

Any executable works as an agent:

- invoked with the task work directory as its working directory;
- the task prompt is in `$BENCH_PROMPT_FILE`;
- environment: `BENCH_TASK`, `BENCH_CONDITION`, `BENCH_ATTEMPT`,
  `BENCH_VARIANT`, `BENCH_FEEDBACK_FILE` (compiler output from the previous
  attempt), `BENCH_SKILL_FILE` (skill path, condition D),
  `BENCH_DOCS_CMD` (lookup command, conditions C and D), `BENCH_METRICS`
  (write a JSON file here);
- it edits files in the work directory and exits.

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
   gleeunit reports `No tests found!`, or when fewer tests ran than
   `visible_tests + hidden_tests`;
3. removes the hidden file again so the next attempt cannot see it.

Prove the guard works:

```sh
./benchmarks/harness/run.sh --self-check
```

It deliberately breaks discovery in two ways (hidden test outside `test/`, and
an entry module that stops calling `gleeunit.main()`) and fails unless both are
refused.

## Running

```sh
./benchmarks/harness/run.sh                          # all tasks, all conditions, fixture agent
./benchmarks/harness/run.sh --tasks word-frequency   # one task
./benchmarks/harness/run.sh --conditions A,C         # chosen conditions
./benchmarks/harness/run.sh --agent ./my-agent.sh --json results.json
```

Output goes to `/tmp/gleam-bench` by default (`--out` to change).

A real agent adapter is a thin wrapper that passes the prompt to the model,
applies its edits to the current directory, and writes `$BENCH_METRICS`. Keep it
outside this repository if it needs credentials; nothing here should contain
one.

## Fixture results on this machine

Measured 2026-11-02, Gleam 1.19.2, OTP 29, Node 23.11.1, `gleam_stdlib` 1.0.5,
`gleeunit` 1.11.0, fixture agent, 6 tasks × 4 conditions (24 runs):

| Task | A final | B first → final | C first → final | D first → final |
| --- | --- | --- | --- | --- |
| `word-frequency` | fail | fail → pass (2 attempts) | pass | pass |
| `cart-totals` | fail | fail → pass (2 attempts) | pass | pass |
| `validate-user` | fail | fail → pass (2 attempts) | pass | pass |
| `reuse-format` | fail | fail → pass (2 attempts) | pass | pass |
| `target-split` | fail | fail → pass (2 attempts) | pass | pass |
| `bugfix-pagination` | fail | fail → pass (2 attempts) | pass | pass |
| **totals** | **0/6** | **0/6 → 6/6** | **6/6** | **6/6** |

The failures are the ones the recorded attempts encode: an invented
`dict.update`, a missing `Fixed` match arm, a stub that returns `Ok`
unconditionally, a duplicated truncation helper with an off-by-one, a
hardcoded Erlang origin, and a 1-based pagination bug. A/B/C/D are the harness
distinguishing the recorded attempts; they are not a measured improvement from
the toolkit, because no model was involved.

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
