# Standard library and dependencies

Load this when you need a function you have not used in this project, when you
are unsure which module owns a concept, or when the pinned versions matter.

## The rule

Never write a standard-library call from memory. Verify it:

```sh
gleam-api sig gleam/list.fold        # exact signature, package, version
gleam-api find <name>                # all public symbols with this name
gleam-api search <purpose words>     # search names and documentation
gleam-api type <TypeName>            # custom type, variants, fields
gleam-api module gleam/dict          # one line per public symbol
gleam-api packages                   # compiler version + locked dependency versions
```

Output names the owning package and its locked version, for example:

```
gleam_stdlib 1.0.5  gleam/dict  (build/packages/gleam_stdlib/src/gleam/dict.gleam:446)
  pub fn upsert(in dict: Dict(k, v), update key: k, with fun: fn(Option(v)) -> v) -> Dict(k, v)
```

That `1.0.5` is the version the compiler will actually use, taken from
`manifest.toml`. Documentation for a newer release is not evidence.

## Fallback order

1. Installed sources: `build/packages/<package>/src/**/*.gleam` and
   `src/**/*.gleam`. Offline, exact, no setup.
2. Compiler interfaces: `gleam export package-interface` for the current
   package (JSON with functions, types, and per-target capability flags), or
   `gleam build` to prove a call type-checks.
3. Version-pinned published docs:
   `https://hexdocs.pm/<package>/<version>/<module>.html`.
   Optional extra: `gleamdoc`, only when the project already depends on it —
   `gleam run -m gleamdoc -- search "<text>" --json=TRUE`.

If a symbol appears in none of these, it does not exist in this project.

## `gleam_stdlib` 1.0.5 module map

Verified for the pinned version: `gleam/bit_array`, `gleam/bool`,
`gleam/bytes_tree`, `gleam/dict`, `gleam/dynamic`, `gleam/dynamic/decode`,
`gleam/float`, `gleam/function`, `gleam/int`, `gleam/io`, `gleam/list`,
`gleam/option`, `gleam/order`, `gleam/pair`, `gleam/result`, `gleam/set`,
`gleam/string`, `gleam/string_tree`, `gleam/uri`.

Where concepts live:

- Lists, mapping, folding, grouping: `gleam/list`.
- Key/value maps: `gleam/dict` (`upsert`, `insert`, `get`, `merge`, `group`,
  `fold`, `delete`, `drop`, `keys`, `values`, `to_list`, `from_list`).
- Unique membership: `gleam/set`.
- Text: `gleam/string` (bare names such as `append`, `split`, `trim`, `replace`).
- Numbers: `gleam/int` (`parse`, `to_string`, `sum`, `clamp`, `divide`),
  `gleam/float` (`parse`, `to_string`, `round`, `ceiling`, `truncate`).
- Failure: `gleam/result` (`map`, `map_error`, `try`, `unwrap`, `flatten`, `all`).
- Absence: `gleam/option` (`map`, `unwrap`, `then`, `or`, `to_result`).
- Untrusted input, JSON-shaped data: `gleam/dynamic` and
  `gleam/dynamic/decode`; decode into a typed value, do not pattern match on
  `Dynamic` by hand.
- Bytes and performance-sensitive text: `gleam/bit_array`, `gleam/bytes_tree`.
- URLs: `gleam/uri`.

Known verified absence: `dict.update` does not exist in 1.0.5. The equivalent
is `dict.upsert(dict, key, fn(Option(v)) -> v)`.

## Dependencies

- `gleam.toml` lists ranges; `manifest.toml` pins exact versions. The manifest
  is what the compiler uses; commit it.
- Add a dependency with `gleam add <package>` (or `gleam add --dev <package>`
  for test-only code). Hand-editing `gleam.toml` without running a build leaves
  the manifest stale.
- Dependency source appears under `build/packages/<package>/src/` after the
  first build. `gleam-api` reads exactly those files.
- Ecosystem packages that commonly matter: `gleeunit` (tests), `gleam_erlang`
  and `gleam_otp` (processes and supervision), `gleam_json`, `gleam_http`,
  `wisp` (web), `lustre` (frontend). Check the pinned version before using any
  of their APIs.
- Adding a dependency is a product decision. Prefer the standard library and
  existing dependencies; explain why a new one is needed.
