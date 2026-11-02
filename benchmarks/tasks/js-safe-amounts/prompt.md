# Amounts that mean the same thing on both targets

This project builds for the Erlang target and the JavaScript target. Gleam's
`Int` is arbitrary precision on the BEAM and an IEEE double on JavaScript, so
the two targets disagree above `9_007_199_254_740_991`.

`src/amount.gleam` has two stubs:

```gleam
pub fn parse(text: String) -> Result(Int, Error)
pub fn format(cents: Int) -> String
```

Implement both:

- `parse` trims surrounding whitespace, then:
  - returns `Error(Empty)` for an empty string;
  - returns `Error(NotADigit)` when the text is not entirely decimal digits
    (no sign, no separators, no decimal point);
  - returns `Error(Unrepresentable)` when the number is larger than
    `9_007_199_254_740_991`, because the JavaScript target cannot hold it
    exactly and this module must behave the same on both targets;
  - otherwise returns `Ok(value)`.
- `format` renders whole cents as `<units>.<two digits>`: `7` is `"0.07"`,
  `100` is `"1.00"`, `123456789` is `"1234567.89"`. Use integer arithmetic;
  float division and `float.to_string` do not format identically on the two
  targets.

`Error` already declares the three variants you need.

The visible test covers a small amount. Keep it passing, and do not change its
expectations.
