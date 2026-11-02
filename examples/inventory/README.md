# Inventory

An in-memory stock example that shows a boundary rather than a framework. The
rules are pure, the store is a value, and there is no process and no database.

## Module shape

```text
inventory          public functions and type aliases
├── item           Sku and Item values
├── movement       Movement, StockError, apply_movement (pure core)
└── store          immutable Dict-backed store (boundary)
```

`inventory` depends on the other three. `store` depends on `item` and
`movement`; `movement` depends only on `item`. There are no cycles and no
target-specific externals, so the same modules compile for Erlang and
JavaScript.

## The pure core

`apply_movement(item, movement) -> Result(Item, StockError)` contains every
stock rule. It rejects a movement for a different SKU, non-positive receipts or
issues, issues larger than the stock on hand, and negative stock levels. It
returns a new `Item` and never changes the argument.

`Movement` has three variants: `Receive`, `Issue`, and `SetLevel`. `SetLevel`
is an absolute stocktake, so applying it twice is naturally idempotent. That is
useful when a stocktake must be retried. `Receive` and `Issue` are relative and
are intentionally not idempotent.

## The store boundary

`store.Store` wraps `Dict(Sku, Item)`. `put` and `apply` take a store and
return a new store; nothing mutates in place. `apply` looks up the item named
by the movement, calls the pure core, and only then writes the updated item
back. `apply_all` uses `list.try_fold`: one failing step rejects the batch, and
the caller still holds the original store value, so there is no partial state
to roll back.

The store is an ordinary module because the data is small, access is
single-threaded within a request or test, and callers want to choose when a new
snapshot becomes visible. Passing the store explicitly also makes tests
straightforward: a test builds a store value and inspects what comes back.

## Why not an OTP actor?

An actor earns its keep when it owns something that must be serialized or kept
alive independently of the caller: concurrent writers sharing one stock ledger,
a cache that must survive requests, or work that continues after the caller
returns. This example has none of those. A process here would add message
ordering, timeouts, supervision, and shutdown concerns in exchange for no
behaviour the ordinary module cannot provide.

If the example grew a web handler with several concurrent requests updating
the same live stock, the next step would be a `gen_server`-style actor (or a
database transaction) that owns the `Dict` and applies movements one at a time.
The pure `apply_movement` function would remain unchanged inside that owner,
which is the point of keeping the rules separate from the storage decision.

## Unknown SKUs

`UnknownSku` can arise at either layer. The store raises it while looking up a
movement that names a SKU it does not hold. The core raises it when it is given
an item and a movement for different SKUs, which guards against mispairing at
the boundary.

## Running

```sh
gleam test
gleam build --target javascript
gleam test --target javascript
```

Tests cover the rejection paths, idempotent `SetLevel` application, all-or-
nothing batch application, and multi-step sequences. They run unchanged on
both targets.
