# Stock transfers across three modules

A small warehouse keeps an on-hand quantity per SKU.

- `src/stock.gleam` holds the `Stock` type (a `Dict`), `Transfer`, and accessors.
- `src/limits.gleam` holds the quantity rules shared by every movement:
  `limits.clamp_quantity(quantity)` keeps a quantity between zero and
  `limits.max_per_transfer`.
- `src/transfer.gleam` decides one movement.
- `src/batch.gleam` applies a list of movements.

Two functions are stubs:

```gleam
// src/transfer.gleam
pub fn apply(inventory: stock.Stock, transfer: stock.Transfer) -> Result(stock.Stock, Error)

// src/batch.gleam
pub fn apply_all(inventory: stock.Stock, transfers: List(stock.Transfer))
  -> #(stock.Stock, List(transfer.Error))
```

Implement both:

- `apply` rejects a SKU that is not in the stock with `Error(UnknownSku(sku))`.
  For a known SKU it clamps the quantity with `limits.clamp_quantity`, rejects
  a clamped quantity of zero with `Error(NothingToMove(sku))`, and otherwise
  returns `Ok` with the quantity added to the on-hand amount.
- `apply_all` applies the movements in order, keeps the stock from every
  accepted movement, leaves the stock unchanged for a rejected one, and
  collects the errors in the order they happened.

Use `limits.clamp_quantity` and the `stock` accessors. Do not reimplement the
clamping or the quantity limit in `transfer.gleam` — that rule already has an
owner.

The visible test in `test/` covers one accepted movement. Keep it passing, and
do not change its expectations.
