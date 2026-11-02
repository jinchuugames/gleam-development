# Report headlines

`src/text_format.gleam` already provides the text shortener used across the
project:

```gleam
pub fn shorten(text: String, max: Int) -> String
```

It trims surrounding whitespace and truncates the text to `max` characters,
appending `"..."` when the text is longer than that.

Implement `headline` in `src/report.gleam`:

```gleam
pub fn headline(title: String) -> String
```

`headline` must shorten the title to 30 characters using the existing
`text_format.shorten`, then uppercase only the first character, leaving the rest
of the shortened text unchanged.

Reuse `text_format.shorten`. Do not reimplement the truncation logic in
`report.gleam`.

The visible tests in `test/` cover the basic case. Keep them passing, and do
not change their expectations.
