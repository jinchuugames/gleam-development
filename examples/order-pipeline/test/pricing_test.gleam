import gleam/list
import order_pipeline
import order_pipeline/order.{Draft, Order}

pub fn line_total_multiplies_quantity_by_price_test() {
  let line = order_pipeline.line_item("SKU-1", 3, 250)
  assert order_pipeline.line_total(line) == 750
}

pub fn subtotal_sums_every_line_test() {
  let order =
    order_pipeline.new_order("A-1")
    |> order_pipeline.add_line(order_pipeline.line_item("SKU-1", 2, 500))
    |> order_pipeline.add_line(order_pipeline.line_item("SKU-2", 1, 1200))

  assert order_pipeline.subtotal(order) == 2200
}

pub fn empty_order_subtotal_is_zero_test() {
  let order = Order(id: "A-1", status: Draft, lines: [])
  assert order_pipeline.subtotal(order) == 0
}

pub fn totals_by_sku_aggregates_repeated_skus_test() {
  let lines = [
    order_pipeline.line_item("SKU-1", 2, 500),
    order_pipeline.line_item("SKU-2", 1, 1200),
    order_pipeline.line_item("SKU-1", 3, 500),
  ]

  assert order_pipeline.totals_by_sku(lines)
    == [#("SKU-1", 2500), #("SKU-2", 1200)]
}

pub fn totals_by_sku_are_sorted_by_sku_test() {
  let lines = [
    order_pipeline.line_item("SKU-9", 1, 100),
    order_pipeline.line_item("SKU-2", 1, 100),
    order_pipeline.line_item("SKU-5", 1, 100),
  ]

  assert order_pipeline.totals_by_sku(lines)
    == [#("SKU-2", 100), #("SKU-5", 100), #("SKU-9", 100)]
}

pub fn totals_by_sku_of_no_lines_is_empty_test() {
  assert order_pipeline.totals_by_sku([]) == []
}

pub fn subtotal_matches_the_sum_of_per_sku_totals_test() {
  let lines = [
    order_pipeline.line_item("SKU-1", 2, 500),
    order_pipeline.line_item("SKU-1", 1, 500),
    order_pipeline.line_item("SKU-3", 4, 75),
  ]
  let order =
    lines
    |> list.fold(order_pipeline.new_order("A-1"), order_pipeline.add_line)

  let per_sku_total =
    order_pipeline.totals_by_sku(lines)
    |> list.fold(0, fn(total, entry) { total + entry.1 })

  assert order_pipeline.subtotal(order) == per_sku_total
}
