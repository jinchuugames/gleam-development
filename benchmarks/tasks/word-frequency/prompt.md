# Word frequency

Implement two functions in `src/word_frequency.gleam`:

```gleam
pub fn count_words(text: String) -> Dict(String, Int)
pub fn top_words(text: String, limit: Int) -> List(#(String, Int))
```

`count_words` lowercases the text, splits it on single spaces, drops empty
words, and returns how often each word occurs.

`top_words` returns the most frequent words first; ties are ordered
alphabetically. `limit` is the maximum number of pairs returned, and a limit of
zero or less returns an empty list.

The visible tests in `test/` cover the basic cases. Keep them passing, and do
not change their expectations.
