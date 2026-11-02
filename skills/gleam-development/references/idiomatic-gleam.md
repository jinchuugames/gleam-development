# Idiomatic Gleam

Load this when writing new modules or reviewing a diff for patterns borrowed
from another language.

## Translate the instinct, not the syntax

| Instinct from another language | Gleam |
| --- | --- |
| `nil` / `null` / `undefined` checks | `Option(a)` with `Some`/`None`; the compiler forces both branches |
| exceptions / `throw` / `try/catch` | `Result(a, e)` returned and matched; panics are for bugs, not control flow |
| class or interface hierarchies | custom types with variants, plus functions per variant |
| `enum` + `switch` with a default | custom type + exhaustive `case`; there is no default, add all variants |
| mutating an object, then returning it | take the value, return a new value |
| stringly-typed state (`"active"`) | a custom type with one variant per state |
| `for` loops | `list.map`, `list.filter`, `list.fold`, `list.try_each`, piping |
| early-return with `if` chains | `case`, `use` expressions, or a small helper returning `Result` |
| monkey patching / dynamic dispatch | pass the function as an argument |
| macros / metaprogramming | there is none; write the code |

## Types carry the domain

```gleam
pub type Status {
  Draft
  Placed(at: Int)
  Shipped(at: Int, tracking: String)
  Cancelled(reason: String)
}
```

Rules of thumb:

- A public type should make an invalid state unrepresentable where it is cheap
  to do so. If `Placed` always has a timestamp, put it in the variant.
- Name the error type after the failure, not after the function:
  `EmptyCart`, `NegativeQuantity(Int)`, `UnknownSku(String)`.
- Do not expose internal types as `pub` unless a caller must construct or match
  them. `pub opaque type` keeps invariants when construction must be guarded.

## Functions

- Explicit parameter types on public functions; inference is fine inside.
- Use argument labels (`with fun:`, `in dict:`) when a call site would otherwise
  read as pure positional noise; call with `function(arg, label: value)`.
- Keep functions small enough to read in one screen. Extract pure helpers
  instead of long `case` bodies.
- Prefer pattern matching in the function head for one-variant cases and `case`
  in the body when several variants share work.

## Pipelines

```gleam
items
|> list.filter(fn(item) { item.quantity > 0 })
|> list.map(fn(item) { item.price * item.quantity })
|> int.sum
```

Pipe when the data flow is the point. Do not pipe into a function whose first
argument is not the data, and do not pipe a single call just for style.

## Records and updates

Gleam has no record-update syntax. Write a small function that returns a copy:

```gleam
fn with_status(order: Order, status: Status) -> Order {
  Order(..order, status: status)
}
```

This keeps the change in one place instead of repeating `Order(..order, ...)`
at every call site.

## Things that look clever and are not

- Recursion where `list.fold` or `list.map` says the same thing.
- A module per type. Group by domain concept; three small modules beat ten
  one-function modules.
- An abstraction with one implementation. Add it when the second caller
  appears.
- `let assert` in library code: it turns a recoverable failure into a crash.
  Reserve it for tests and for invariants that are genuinely impossible.
- Boolean flags in a public API (`fn run(verbose: Bool, dry_run: Bool)`).
  A custom type with variants stays readable when a third flag arrives.
