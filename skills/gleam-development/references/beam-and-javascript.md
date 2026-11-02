# BEAM and JavaScript targets

Load this when the project targets JavaScript as well as Erlang, when adding an
external function, or when a test passes on one target and fails on the other.

## What a target means

- `target = "erlang"` or `target = "javascript"` in `gleam.toml` is the default;
  `gleam build --target javascript` overrides it per command.
- Every source file must compile for the target being built. A module using
  Erlang-only packages (`gleam_erlang`, `gleam_otp`) fails a JavaScript build
  unless it is gated.
- Per-function capability flags for your own package:

  ```sh
  gleam export package-interface | jq '.modules[].functions | to_entries[] | {name: .key, impl: .value.implementations}'
  ```

  Flags include `can-run-on-erlang`, `can-run-on-javascript`,
  `uses-erlang-externals`, `uses-javascript-externals`.

## Gating target-specific code

```gleam
@target(erlang)
pub fn now_monotonic() -> Int { /* Erlang external */ }

@target(javascript)
pub fn now_monotonic() -> Int { /* JavaScript external */ }
```

Keep two rules: the shared module declares the same public name for both
targets, and the pure logic calling it does not care which one it got. If a
feature genuinely exists on one target only, gate the module and make the
JavaScript build not import it.

## Externals

```gleam
@external(erlang, "erlang", "system_time")
@external(javascript, "./time_ffi.mjs", "systemTime")
fn system_time() -> Int
```

- External names are unchecked strings. A typo compiles and fails at runtime,
  on that target only. Test both targets if you add one.
- Keep the external module thin: one or two functions, no business logic.
- Prefer a maintained package over a hand-written external.

## Runtime differences that bite

| Area | Erlang | JavaScript |
| --- | --- | --- |
| Processes | full OTP | none; use promises/callbacks or a package |
| Integers | arbitrary precision | 53-bit safe integers; `int` operations overflow differently |
| Floats | Erlang float formatting | JavaScript `Number` formatting; `float.to_string` can differ |
| Dictionary order | not guaranteed | insertion order |
| String/bytes | UTF-8 binaries | UTF-8 strings; `bit_array` uses `Uint8Array` |
| Errors | `panic` becomes an exit | `panic` throws an exception |
| Runtime | `erl`/OTP 29 here | Node 23 by default, `--runtime deno`, `--runtime bun` |

Consequences: do not compare formatted floats across targets; sort collections
before asserting; do not assume a process API exists in shared code.

## Commands

```sh
gleam build                                  # default target
gleam build --target javascript
gleam test                                   # erlang
gleam test --target javascript               # node
gleam test --target javascript --runtime deno
gleam export erlang-shipment                 # deployable Erlang release
gleam export escript                         # single-file Erlang CLI
```

A dual-target change is done only when both builds and both test runs pass, or
when the JavaScript path is explicitly out of scope and the reason is stated.
