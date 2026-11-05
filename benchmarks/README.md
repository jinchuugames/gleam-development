# Benchmark

A model-agnostic harness that measures whether an agent writes correct Gleam,
with and without the toolkit. It never imports a provider SDK and needs no paid
API access for its own validation: a fixture agent replays recorded attempts so
the infrastructure can be exercised offline.

**What it measures:** whether fixture tests pass. **What it does not measure:**
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
The evaluator copies an attempt after the agent exits. It adds acceptance tests to that separate copy.
It removes the copy and its logs before the next attempt.

## Tasks

| Task | Covers |
| --- | --- |
| `word-frequency` | standard-library API verification, dict and list transformations |
| `cart-totals` | custom types, exhaustive pattern matching, integer discount rules |
| `validate-user` | `Result`-based validation, error variants, trimming |
| `reuse-format` | multi-module change, reuse of an existing implementation, duplicate detection |
| `target-split` | Erlang/JavaScript target compatibility, `@target` gating |
| `bugfix-pagination` | bug fix that compiles but is wrong on a boundary |
| `boundary-expiry` | boundary discipline: the clock arrives as an argument, inclusive expiry, clamping |
| `multi-module-transfers` | a change across two modules that must reuse a rule owned by a third |
| `js-safe-amounts` | Erlang/JavaScript behavioural compatibility: `2^53` precision and integer formatting |

Each task has a `work/` project, a `prompt.md`, public fixture tests in `fixture-tests/`, and recorded attempts in `agent/`.
The evaluator never adds fixture tests to the agent's work directory.

## Public fixtures, not private holdouts

The bundled tests are fixture tests, and every one of them is public.
An agent with internet access can obtain them from this repository, so the harness keeps fixture tests out of the agent's work directory but does not hide them.
A separate work directory provides local file separation. It does not provide a filesystem sandbox or network isolation.
An agent with unrestricted host access can also search other host directories.

A real model comparison needs a separate private holdout set, kept in an evaluator the agent cannot reach.
Use an external sandbox or a separate host for that boundary.
This harness has no external-holdout interface.
A score on the public fixtures is never evidence of model capability on its own: it can measure test exposure instead of task skill.
Report a real-agent result only next to a private-holdout result, and label the fixture score as harness validation.

## Layout of a task

```
tasks/<id>/
  meta.json        targets, fixture module name, test counts, expected files, forbidden duplicates
  prompt.md        what the agent is told
  work/            the project handed to the agent (gleam.toml, manifest.toml, src/, test/)
  fixture-tests/zz_fixture_test.gleam
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
other seven replay a recorded failed attempt that changes the source.

## Agent contract

Any executable works as an agent:

- invoked with the task work directory as its working directory;
- the task prompt is in `$BENCH_PROMPT_FILE`;
- environment: `BENCH_TASK`, `BENCH_CONDITION`, `BENCH_ATTEMPT`,
  `BENCH_VARIANT`, `BENCH_FEEDBACK_FILE` (compiler output from the previous
  attempt), `BENCH_METRICS` (write a JSON file here), and only when the
  condition allows it, `BENCH_DOCS_CMD` (C and D) and `BENCH_SKILL_FILE` (D);
- C receives the lookup command under `$out/.stage/`; D also receives the skill;
- the harness removes inherited lookup and skill variables before each launch;
- the harness supplies no fixture-test path. Local file separation is not a security boundary;
- it edits files in the work directory and exits;
- it is killed after `BENCH_AGENT_TIMEOUT` seconds (default 600) and the
  attempt is recorded as failed.

`BENCH_METRICS` accepts one JSON object, for example:

```json
{"files_read": 2, "tokens": 123, "model": "adapter-name"}
```

`files_read` and `tokens` accept non-negative integers up to `9007199254740991`.
Strings, booleans, arrays, objects, negative values, fractions, and larger values become `null`.
Missing fields, absent files, empty files, and invalid JSON also produce `null`.
The harness clears the metrics file before each attempt. A result row uses the last attempt's metrics.
The `model` field in this file is informational; `BENCH_MODEL` supplies the result metadata.
The fixture agent reports `tokens: null`. The summary does not estimate token counts.

## Metrics

`results.json` records, per task and condition:

- `first_attempt_pass`, `final_pass`
- `attempts`, `compiler_iterations` (builds run), `test_iterations`
- `wall_clock_seconds`
- `files_read` and `tokens` (agent-reported), `files_modified`, `unrelated_changes`
- `duplicated_implementations` (forbidden symbols found in `src/`)
- `behavioural_regression` (visible tests failing after the change)

Each result row has this shape:

```json
{
  "task": "word-frequency",
  "condition": "C",
  "first_attempt_pass": true,
  "final_pass": true,
  "attempts": 1,
  "compiler_iterations": 1,
  "test_iterations": 1,
  "wall_clock_seconds": 2,
  "files_read": 2,
  "tokens": null,
  "files_modified": 1,
  "unrelated_changes": 0,
  "duplicated_implementations": 0,
  "behavioural_regression": false
}
```

The top-level object contains `metadata` and `results`.
`metadata` contains `model`, `compiler`, `stdlib`, `wall_clock_seconds`, and `note`.
The values above illustrate the schema; they are not measured model results.

## Test-discovery guard

A pass requires a successful agent exit and acceptance tests on every declared target.
For each target, the evaluator checks the test file, the entry module, and the actual test count.
The fixture run must execute at least `fixture_tests` more tests than the visible run.
Skipped tests do not count as execution. One target cannot supply another target's count.
The evaluator deletes its copy and logs before the next agent attempt.

Prove the guard works:

```sh
./benchmarks/harness/run.sh --self-check
```

It probes each condition's environment (A must receive no toolkit path, C the
lookup command only, D both, and no path may contain the repository root),
breaks discovery in three ways (fixture test outside `test/`, an entry module
that stops calling `gleeunit.main()`, and a hollow fixture test that adds one
trivial pass instead of the expected tests), checks that a hanging agent is
recorded as a timeout, and checks that an adapter which writes no metrics file
still gets its row, with `files_read: null`. It also runs `harness/regression-check.sh` for path safety, inherited variables, relative paths, token transport, retry separation, and per-target discovery.
A timeout after a correct edit must still fail. The self-check fails if any assertion fails.

## Running

```sh
./benchmarks/harness/run.sh                          # all tasks, all conditions, fixture agent
./benchmarks/harness/run.sh --tasks word-frequency   # one task
./benchmarks/harness/run.sh --conditions A,C         # chosen conditions
./benchmarks/harness/run.sh --agent ./my-agent.sh --json results.json
```

Output goes to `/tmp/gleam-bench` by default (`--out` to change). An `--out`
inside the repository is refused before directory creation.
Conditions accept only `A`, `B`, `C`, and `D`. Task IDs accept letters, digits, underscores, and hyphens.
The harness validates the full selection before it writes results.
Existing symlinks inside the output directory cause refusal before cleanup.
Relative agent and output paths resolve before the task starts. Executable paths can contain spaces.
The interface accepts one executable path without arguments. Use an executable wrapper for agent arguments.

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
`gleeunit` 1.11.0, fixture agent, 9 tasks × 4 conditions (36 runs):

| Task | A final | B first → final | C first → final | D first → final |
| --- | --- | --- | --- | --- |
| `word-frequency` | fail | fail → pass (3 attempts) | pass | pass |
| `cart-totals` | fail | fail → pass (3 attempts) | pass | pass |
| `validate-user` | fail | fail → pass (3 attempts) | pass | pass |
| `reuse-format` | fail | fail → pass (3 attempts) | pass | pass |
| `target-split` | fail | fail → pass (3 attempts) | pass | pass |
| `bugfix-pagination` | fail | fail → pass (3 attempts) | pass | pass |
| `boundary-expiry` | fail | fail → pass (3 attempts) | pass | pass |
| `multi-module-transfers` | fail | fail → pass (3 attempts) | pass | pass |
| `js-safe-amounts` | fail | fail → pass (3 attempts) | pass | pass |
| **totals** | **0/9** | **0/9 → 9/9** | **9/9** | **9/9** |

Every B run takes three attempts: the first fails, the recorded repair still
fails the acceptance tests, and the final correction passes. That is the
compiler-feedback cycle, not a single correct file replayed.

The failures are the ones the recorded attempts encode: an invented
`dict.update`, a missing `Fixed` match arm, a stub that returns `Ok`
unconditionally, a duplicated truncation helper with an off-by-one, a
hardcoded Erlang origin, a 1-based pagination bug, an expiry that is still valid
at its own boundary second with a countdown that runs past zero, a copied
quantity rule with the batch function left unimplemented, and an amount parser
that accepts a number the JavaScript target cannot hold. The second B attempt
fixes only the reported problem (compile error, failed assertion) and leaves a
remaining defect, which is why it still fails. A/B/C/D distinguish recorded
attempts; they are not a measured improvement from the toolkit, because no
model was involved.

`duplicated_implementations` is not a dead column: the two tasks with a
`forbidden` list (`reuse-format`, `multi-module-transfers`) report `dups=1` for
condition A, because their recorded first attempt copies the helper. Conditions
that end on the repaired file report `dups=0`.

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
- `fixture_tests` and `visible_tests` in `meta.json` are the guard's
  expectations; keep them correct when editing a task, or the guard will refuse
  honest runs.
