# Greetings from either platform

This project builds for both the Erlang and the JavaScript target.

`src/platform.gleam` already provides the target-specific origin:

```gleam
pub fn origin() -> String
```

It returns `"erlang"` on the Erlang target and `"javascript"` on the JavaScript
target.

Implement `greet` in `src/greeting.gleam`:

```gleam
pub fn greet(name: String) -> String
```

- For a non-empty name, return
  `"hello " <> name <> " from " <> platform.origin()`.
- For an empty or whitespace-only name, return
  `"hello stranger from " <> platform.origin()`.

Call `platform.origin()` rather than hardcoding either origin string; the same
code must behave correctly on both targets.

The visible tests in `test/` cover the stranger case. Keep them passing, and do
not change their expectations.
