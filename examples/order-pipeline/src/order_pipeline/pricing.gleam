//// Pure pricing. It knows about line items and orders, but never about the
//// store, the database, or the network.

import gleam/dict
import gleam/int
import gleam/list
import gleam/option
import gleam/string
import order_pipeline/order.{type LineItem, type Order, type Sku}

pub fn line_total(line: LineItem) -> Int {
  line.quantity * line.unit_price_cents
}

pub fn subtotal(order: Order) -> Int {
  list.fold(order.lines, 0, fn(total, line) { total + line_total(line) })
}

/// Sums the value of every line per SKU. `dict.upsert` is used rather than
/// checking for the key and inserting separately: one lookup, one insert.
///
/// Dict iteration order is deliberately not exposed. Sorting by SKU makes the
/// result deterministic for callers and tests.
pub fn totals_by_sku(lines: List(LineItem)) -> List(#(Sku, Int)) {
  lines
  |> list.fold(dict.new(), fn(totals, line) {
    dict.upsert(totals, line.sku, fn(existing) {
      existing
      |> option.unwrap(0)
      |> int.add(line_total(line))
    })
  })
  |> dict.to_list
  |> list.sort(fn(a, b) { string.compare(a.0, b.0) })
}
