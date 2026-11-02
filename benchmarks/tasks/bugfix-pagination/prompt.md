# Fix pagination

`src/pagination.gleam` provides:

```gleam
pub fn page(items: List(a), page_number: Int, page_size: Int) -> List(a)
```

Pages are 1-based: page 1 returns the first `page_size` items, page 2 the next
`page_size` items, and so on. The final page may be partial. A page number
beyond the end of the list returns an empty list, and page numbers below 1 clamp
to page 1.

The current implementation compiles and passes the visible tests, but it is
wrong on the first page and on every later page. Fix it without changing the
public signature, and keep the visible tests in `test/` passing.
