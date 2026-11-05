# Idiomatic Gleam

Use this reference for new modules and code reviews.

Source: [Gleam conventions, patterns, and anti-patterns](https://gleam.run/documentation/conventions-patterns-and-anti-patterns/).
The official guide sets the language conventions. The notes below apply them to this toolkit.

## Official conventions

- Qualify imported functions and constants: `list.map`.
  Types and constructors can use clear, unqualified imports.
- Use singular module names and words for acronyms: `Json`.
- Name conversions `x_to_y`. Omit `x_` when the module supplies it.
- Use domain names for fallible operations. Reserve `try_` for fallible alternatives.
- Use `Result` for failure, including `Result(value, Nil)` without error detail.
- Reuse core package types and operations.
- Put tool configuration under `[tools.<name>]` in `gleam.toml`.
- Use `src/` for application code, `test/` for tests, and `dev/` for helpers.
- Keep modules inside the package namespace. Group them by domain.
- Match directly instead of a check followed by `let assert`.
- Use concrete FFI types. Use `Dynamic` for unknown shapes.
- Separate request construction from response parsing. The caller owns HTTP transport.
- Use a builder for several optional fields.

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
- Adding a field or a variant is a safe refactor: every constructor and every
  `case` that does not cover it stops compiling, so the error list is the change
  list. Work through it; do not silence it with a `_ ->` arm, which turns
  exhaustiveness off for every future variant as well.
- Name the error type after the failure, not after the function:
  `EmptyCart`, `NegativeQuantity(Int)`, `UnknownSku(String)`.
- A catch-all is fine where the set of values is open: a `String`, an `Int`,
  a list's tail, an error from another package. On a custom type, list the
  variants, even when several share one body:

  ```gleam
  // Wrong: a new Status variant compiles and is silently treated as not shipped.
  case status {
    Shipped(..) -> True
    _ -> False
  }

  // Right: a new variant stops the build here.
  case status {
    Shipped(..) -> True
    Draft | Placed(..) | Cancelled(..) -> False
  }
  ```

  To audit: `grep -rn -B4 "^\s*_ ->" src` and check what each `case` matches on.
- Do not expose internal types as `pub` unless a caller must construct or match
  them. `pub opaque type` keeps invariants when construction must be guarded.

## Functions

- Annotate parameters and return types on every module function, including private functions.
  Local expressions can use type inference.
- Use argument labels (`with fun:`, `in dict:`) when a call site would otherwise
  read as pure positional noise; call with `function(arg, label: value)`.
- Keep functions small enough to read in one screen. Extract pure helpers
  instead of long `case` bodies.
- Match values with `case` or `let` inside the function body.
  Gleam function parameters do not support destructuring patterns.

## Comments

Gleam has three comment kinds, and each has one job:

- `////` at the top of a module: what the module owns and what it does not.
  A few lines, so a reader can decide whether to keep reading.
- `///` above a public function, type or constant: what a caller needs to
  know. These become the generated docs (`gleam docs build`).
- `//` inside code: a reason the code cannot show, such as a workaround, a
  bound, or why the obvious version is wrong.

Keep them short. A comment that retells the code, narrates the change ("moved
here from X"), or argues a design over several paragraphs goes stale the first
time the code changes, and nothing checks it. Put history in the commit
message and design arguments in a design doc. As a rough check, if a module's
comments outweigh its code, cut them.

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

Gleam has no mutation: `..record` builds a new value with some fields replaced.
That spread is the record-update syntax; what it does not do is mutate in place.
Use it directly for a one-off change, and wrap it in a small function when the
same spread repeats at many call sites:

```gleam
fn with_status(order: Order, status: Status) -> Order {
  Order(..order, status: status)
}
```

The wrapper keeps the field list in one place; it does not make the update
mutable.

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
