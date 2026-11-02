//// The public entry point for the example. It re-exports the domain types and
//// exposes a small, stable set of functions. Consumers that need to pattern
//// match on `Status` or an error variant import `order_pipeline/order`
//// directly, since Gleam type aliases do not re-export constructors.

import order_pipeline/order as domain
import order_pipeline/pricing

pub type Sku =
  domain.Sku

pub type LineItem =
  domain.LineItem

pub type Status =
  domain.Status

pub type Order =
  domain.Order

pub type TransitionError =
  domain.TransitionError

pub type ValidationError =
  domain.ValidationError

pub fn line_item(
  sku: String,
  quantity: Int,
  unit_price_cents: Int,
) -> LineItem {
  domain.LineItem(
    sku: sku,
    quantity: quantity,
    unit_price_cents: unit_price_cents,
  )
}

pub fn new_order(id: String) -> Order {
  domain.new(id)
}

pub fn add_line(order: Order, line: LineItem) -> Order {
  domain.add_line(order, line)
}

pub fn status(order: Order) -> Status {
  order.status
}

pub fn transition(order: Order, to: Status) -> Result(Order, TransitionError) {
  domain.transition(order, to)
}

pub fn validate_line(line: LineItem) -> Result(LineItem, ValidationError) {
  domain.validate_line(line)
}

pub fn validate_lines(
  lines: List(LineItem),
) -> Result(List(LineItem), ValidationError) {
  domain.validate_lines(lines)
}

pub fn validate(order: Order) -> Result(Order, ValidationError) {
  domain.validate(order)
}

pub fn subtotal(order: Order) -> Int {
  pricing.subtotal(order)
}

pub fn line_total(line: LineItem) -> Int {
  pricing.line_total(line)
}

pub fn totals_by_sku(lines: List(LineItem)) -> List(#(Sku, Int)) {
  pricing.totals_by_sku(lines)
}
