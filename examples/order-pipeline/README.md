# Order pipeline

A small Gleam example of order pricing and lifecycle state. It is deliberately
pure: no database, no processes, and no target-specific code.

## Module shape

```text
order_pipeline          public functions and type aliases
├── order               domain types, validation, state machine
└── pricing             subtotal and per-SKU totals
```

Dependencies point one way. `order_pipeline` imports both internal modules,
`pricing` imports `order` for its line-item type, and nothing imports the
facade. That keeps the domain reusable and stops the public surface from
becoming a hub that every module depends on.

## Values instead of mutations

`Order` is an immutable value. `transition` takes an order and a target status
and returns either a new order or `IllegalTransition(from, to)`. The complete
state machine is one exhaustive `case`:

```text
Draft     -> Placed | Cancelled
Placed    -> Shipped | Cancelled
Shipped   -> terminal
Cancelled -> terminal
```

Because the transition table lives in one function, an illegal move cannot be
expressed through some other helper. The error carries both statuses, so a
caller can report exactly what was attempted. Nothing is stored globally, which
makes every sequence reproducible in a test.

## Validation at the edge

`validate_line` checks one line in isolation: quantity must be positive and the
unit price must be positive. `validate_lines` adds the order-level rule that no
SKU may appear twice, using a `Dict` as the set of SKUs already accepted.
Errors are values, not panics: each variant names the SKU and the offending
value (`NonPositiveQuantity`, `NonPositivePrice`, `DuplicateSku`).

Validation is a separate step from `transition`. Placing an order is a business
decision that should only follow a clean validation, but keeping the two
functions apart means the state machine stays independent of pricing and
catalogue rules. The caller composes them with `Result`.

## Pricing

Money is represented as integer cents. Integer arithmetic avoids floating-point
rounding, and the example only prices in one currency.

`subtotal` folds over every line. `totals_by_sku` uses `dict.upsert` to
accumulate per-SKU values in a single pass, then sorts by SKU before returning.
The sort matters: `Dict` iteration order is not part of its contract, so
producing a sorted list gives callers and tests a stable result.

## What is intentionally absent

There is no actor, database, or HTTP boundary. The whole example is a pure
library, so introducing a process would add failure modes without buying
concurrency or durability. Persistence belongs in a caller that loads an
order, applies these functions, and writes the result back.

## Running

```sh
gleam test
```

Tests are split by concern: `order_pipeline_test.gleam` covers the state
machine and the happy path, `validation_test.gleam` covers each rejection
branch, and `pricing_test.gleam` covers totals and aggregation.
