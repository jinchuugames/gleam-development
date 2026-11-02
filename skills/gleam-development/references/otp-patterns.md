# OTP patterns

Load this when you are about to add a process, a supervisor, shared mutable
state, or a long-lived timer.

## First question: does this need to be a process?

| Need | Use |
| --- | --- |
| Pure transformation | a function |
| State for the duration of a request | a value passed in and returned |
| State shared by several callers | a store the caller owns, or a process |
| Concurrency | `gleam/otp/actor` or supervised tasks |
| Crash isolation or restart policy | a supervisor |
| Periodic work | a supervised actor with a timer |

An ordinary module holding a `Dict` that the caller passes in is usually the
right answer — deterministic, testable, and identical on the JavaScript target.
A process is justified when state must be shared concurrently, must outlive the
call, or must be supervised.

## If a process is justified

- Put the pure rules in their own module; the actor is a thin shell that
  receives a message, applies the rule, and continues with the new state.
- Keep the message type small and explicit: one custom type per actor.
- Model the actor's state as a custom type, not a tuple of loose values.
- Return `Next` from the handler: `actor.continue(state)` or `actor.stop()`.
- Expose a small client API (send a message, wait for a reply) instead of
  leaking pids to callers.
- Supervision belongs with the application boundary: build the supervisor in
  the entry module, not inside library code.

Verified surface in `gleam_otp 1.3.0` (pinned versions change; re-check with
`"$gleam_api" module gleam/otp/actor`):

- `gleam/otp/actor`: `actor.start`, `actor.continue`, `actor.stop`; `Next`
  is opaque, built with `actor.continue(state)` or `actor.stop()`; `Started(data)`
  is the public constructor for a started actor.
- `gleam/otp/static_supervisor`: `new(strategy)`, `Strategy(OneForOne,
  OneForAll, RestForOne)`, builder functions such as `restart_tolerance`,
  `auto_shutdown`.
- `gleam/erlang/process`: `Subject(message)`, `new_name`, `named_subject`,
  `send`, `receive`, `spawn`.

Check every name and signature with `gleam-api` before use — this list is a map
of what exists, not a substitute for the signature.

## Smells

- A process with no concurrent callers: pass the state instead.
- A global named process used as a mutable variable: it hides dependency order
  and makes tests order-dependent.
- `actor` inside a domain module: the domain becomes untestable without a
  runtime.
- One supervisor per module: supervisors belong to application boundaries.
- Timers used as a scheduler when a plain function call would do.

## JavaScript target

`gleam_otp` and `gleam_erlang` are Erlang-specific. If the project also targets
JavaScript, keep the domain pure and gate the process layer behind
`@target(erlang)` modules or a separate entry module, and check that shared
modules do not import them.
