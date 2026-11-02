# Where Gleam is weaker

This is the counterweight to the rest of the toolkit. The skill exists because
Gleam is a good fit for agent-written code, and every one of those arguments
has a cost on the other side of the ledger.

Status markers used throughout:

- **reproduced**: a command was run here and the result is quoted in
  `docs/research.md`.
- **author report**: an experience report from the two Curling IO articles
  supplied as research input. Not measured here.
- **opinion**: a judgement, with the reasoning shown so it can be argued with.

The two articles are *AI Agents Love Gleam* and *Why We Chose Rust for Version
3*. The second is the same team leaving Gleam for Rust and TypeScript, which
makes it the most useful evidence in this document: it is a list of costs from
people who had already shipped a Gleam system.

## Summary

| Cost | Status | Evidence |
| --- | --- | --- |
| Fewer libraries, younger ecosystem | reproduced | `docs/research.md`: `gleamdoc` at 0.4.1, single maintainer; no maintained offline code-intelligence server exists |
| Agents write worse first drafts | reproduced | the toolkit's own fixtures encode the failure: an invented `dict.update`, a hardcoded origin, a duplicated helper |
| Packaging native dependencies for an Erlang release is awkward | author report | NIF for SQLite plus release packaging; we have not built a release with a NIF |
| The BEAM is a cost unless you use it | author report | they kept durable job state in SQLite and needed little OTP-specific behaviour |
| No macros, no derives | reproduced | Gleam 1.19.2 has no macro system; serialisation and codegen are separate steps |
| The JavaScript target is not the Erlang target | reproduced | `int.parse("9007199254740993")` gives `Ok(9007199254740993)` on the BEAM and `Ok(9007199254740992)` on JavaScript; `float.to_string(0.000001)` is `1.0e-6` on the BEAM and `0.000001` on JavaScript |
| Thin frontend ecosystem | reproduced | `lustre 5.7.1` has no drag-and-drop helpers in `lustre/event` and no DOM animation helper (the only animation symbols are SVG SMIL elements) |
| Compiling is not correctness | reproduced | the `bugfix-pagination` and `js-safe-amounts` fixtures compile and are wrong |
| Debugging is print-and-reason | reproduced | `gleam/io` 1.0.5 exposes only `print`, `println`, `print_error`, `println_error`; no `io.debug`, no step debugger in the toolkit |

## Deployment

**Author report.** Their specific complaint was packaging SQLite's native
component: the integration used a NIF, so a release needed a Linux build
environment close to production, with the toolchain to compile and link, and
extra components on the production host. With Rust they build Linux releases on
the development machine and upload the artefact.

**Reproduced:** nothing. This toolkit does not build an Erlang release and has
no NIF dependency, so it cannot confirm or deny the difficulty. What can be
stated as fact is the shape of the problem: a NIF is native code, and a release
has to carry a binary compiled for the production architecture.

**Opinion:** if the project uses a pure-Gleam dependency stack and deploys
`gleam export erlang-shipment` to a host with Erlang installed, this cost is
small. It grows the moment a native dependency enters, and it is the single
most credible reason in the articles to leave.

## The BEAM is a decision, not a bonus

**Author report.** They needed durable job state in SQLite regardless of the
runtime, so persistence was not something the BEAM could give them. They used
concurrency and process management but judged that Rust with Tokio met the
workload, and accepted losing supervision and process isolation.

**Opinion:** the toolkit's `references/otp-patterns.md` says the same thing from
the other direction — do not add a process unless state must be shared
concurrently, outlive a call, or survive a crash. A Gleam service that adds a
process per feature pays for the BEAM without collecting on it. If the project
needs hot code reloading, supervision trees, or millions of cheap concurrent
actors, the trade is the other way and Rust is the wrong choice.

## Ecosystem and maintenance risk

**Reproduced.** `docs/research.md` records the survey: `gleamdoc` is at 0.4.1,
published 2026-10-11, with a single maintainer and a few hundred all-time
downloads; no maintained Gleam code-intelligence MCP server exists; the existing
agent skills for Gleam cover the actor model and interop, not dependency API
lookup. `lustre 5.7.1` pulls in `houdini`.

**Opinion:** a small ecosystem means fewer sinks for a duplicated concern, and
more single-maintainer packages in the dependency graph. This toolkit's answer
is to verify installed source rather than trust training data, but that does not
make a package maintained.

## Agents write worse Gleam on the first attempt

**Reproduced, in this repository's own fixtures.** The benchmark records the
failures agents actually produced in these tasks: a call to `dict.update`, which
does not exist in `gleam_stdlib` 1.0.5; a hardcoded `"erlang"` origin in a
dual-target module; a truncation helper copied from an existing module with an
off-by-one; a validation stub that returns `Ok` unconditionally.

**Author report.** They describe the same pattern and the same conclusion: the
first pass is slower in Gleam than in JavaScript, and the total time to correct
and deployed code is shorter because the compiler closes the loop.

**Opinion:** the honest reading is that the compiler converts a review-time cost
into a compile-time cost. It does not remove the cost.

## No macros, no derives

**Reproduced.** Gleam 1.19.2 has no macro system and no derive mechanism.
Serialisation, database row mapping, and route generation are written by hand,
generated by a separate program, or taken from a library.

**Author report.** Two of the reasons they preferred Rust were derive macros
(Serde) and the code generators built on them (Marmot for typed SQL, Proute for
routes). They also note the cost of that machinery: the generators are
substantial code they own and maintain, and generation catches interface
mistakes, not business-rule mistakes.

**Opinion:** prefer generating Gleam over hand-writing the same shape five
times, and count the generator as code you own. Their own generator extraction
is a good example of the second half of that sentence.

## The JavaScript target is a second runtime with the same syntax

**Reproduced, on `gleam 1.19.2`:**

```
$ gleam run                              # Erlang target
parse 9007199254740993: Ok(9007199254740993)
literal: 9007199254740993
sum: 9007199254740993

$ gleam run --target javascript
parse 9007199254740993: Ok(9007199254740992)
literal: 9007199254740992
sum: 9007199254740992
```

And formatting:

```
float.to_string(0.000001)   # 1.0e-6 on the BEAM, 0.000001 on JavaScript
float.to_string(-0.0)       # -0.0 on the BEAM, 0.0 on JavaScript
```

None of that is a compile error on either target. A shared module that does
arithmetic above `9_007_199_254_740_991` or formats a float is correct on one
target and wrong on the other, and only a test run on both targets finds it.
`references/beam-and-javascript.md` lists the differences; the
`js-safe-amounts` benchmark task makes the numeric one a task.

**Opinion:** treat "builds for JavaScript" as a portability claim you have to
earn with tests on both targets, not as a free second platform.

## Frontend

**Reproduced for `lustre 5.7.1`:** `lustre/event` has no drag-and-drop events
(`dragstart`, `drag`, `drop` are not wrapped), and there is no helper for
animating DOM state — the only animation-shaped symbols are the SVG SMIL
elements in `lustre/element/svg`. Drag gestures go through
`event.on(name, decoder)`; animation is CSS.
Shadow DOM is on by default for components (`open_shadow_root: True`,
`adopt_styles: True`), which is good for isolation and means page styles do not
reach inside without `part`/`exportparts`.

**Author report.** Their server-component drawer felt wrong because the round
trip is visible, drag-and-drop made it obvious, and they ended up with a feature
spanning a server tree and a client tree.

**Opinion:** the typed architecture is a real advantage, and the missing pieces
(drag, animation, accessible widgets) are work you do yourself. That is a
smaller ecosystem cost showing up as engineering time, not as a bug.

## Compiling proves types, not behaviour

**Reproduced.** `bugfix-pagination` compiles and returns the wrong page for page
1. `js-safe-amounts` compiles and silently returns a rounded amount. Neither
mistake is a type error, and no amount of `gleam build` catches them.

**Opinion:** this is why the skill schedules a test run with a discovery check
(`references/testing.md`) instead of stopping at a green build, and why the
benchmark grades hidden tests rather than compilation.

## Debugging

**Reproduced.** There is no debugger integration in this toolkit. What exists is
`io.println(string.inspect(value))`, `gleam shell` (an Erlang REPL with the
project's modules loaded), panics with messages, and the test suite as the
reproduction harness. `gleam/io` 1.0.5 has no `io.debug`.

**Author report.** They credit Rust's compiler diagnostics and runtime error
context — the detail in a stack — as the thing that most helped agents trace an
unfamiliar workflow. Gleam's compiler diagnostics are precise for types; its
runtime failure output is an Erlang term.

**Opinion:** the practical gap is runtime observability, not compile-time
guidance. Plan for structured logging and for errors that carry context in the
`Result` value, because there is no stack trace to lean on across a BEAM
process boundary.

## Costs that keep the benchmark honest

**Reproduced.** The benchmark ships nine tasks and a fixture agent that replays
recorded attempts. It measures the harness, not a model. A real run is one
sample of a nondeterministic process, and dependencies need network on the first
build of a task. Any table of results in this repository says what was observed
on one machine on one day.

## What is not a weakness

- **Compile speed.** Measured here at 0.17-0.50 s for the small projects the
  toolkit builds; the article's own complaint about build cost is about Rust
  (a 21.38 s `cargo check` on an unchanged template, a 237 s cold generator
  workflow before extraction), not about Gleam.
- **Formatting arguments.** `gleam format` is canonical and has no
  configuration. That removes a class of review noise rather than adding one.
- **Exhaustiveness.** It is a genuine guarantee, with the one escape hatch the
  compiler permits: a `_ ->` arm turns it off silently.
