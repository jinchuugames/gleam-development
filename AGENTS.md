# Agent notes for this repository

This repository is the toolkit itself, not a Gleam application. The guidance
here is for working on the toolkit.

- `skills/gleam-development/SKILL.md` is the product. Keep it short; put detail
  in `references/` so it loads only when relevant.
- `scripts/gleam-api` reads installed package sources. Any change to it must be
  exercised against a real project with downloaded dependencies, not a mock.
- `docs/research.md` records verified facts with the commands that produced
  them. If a claim stops being true, update it with new evidence; do not append
  guesses.
- `benchmarks/` is model-agnostic: the harness never imports a provider SDK.
  Fixture tasks must compile, their fixture tests must pass against a correct
  solution, and the discovery guard must refuse a run whose tests did not
  execute.
- Run `scripts/check.sh` before claiming anything works. It formats, builds,
  tests, and runs the benchmark self-check.
- This repository must not depend on any private service, model provider, or
  repository outside itself.
