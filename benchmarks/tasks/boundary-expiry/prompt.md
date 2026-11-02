# Session expiry at a boundary

`src/session.gleam` holds a session and its expiry rule. Times are seconds
since the epoch, and they always arrive as arguments: nothing in this module
reads a clock.

Two functions are stubs:

```gleam
pub fn is_expired(session: Session, now: Int) -> Bool
pub fn remaining(session: Session, now: Int) -> Int
```

Implement both:

- `is_expired` returns `True` when `now` is at or after `expires_at(session)`,
  and `False` before it. The expiry second itself is expired.
- `remaining` returns the whole seconds left before expiry, and `0` once the
  session is expired. It never returns a negative number.

Reuse `expires_at`; do not recompute the arithmetic in two places. Both
functions stay pure: `now` is a parameter, and reading a clock would make the
tests flaky.

The visible test in `test/` covers the ordinary countdown. Keep it passing, and
do not change its expectations.
