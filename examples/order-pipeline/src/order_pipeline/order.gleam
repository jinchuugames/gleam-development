//// The order domain: its data types, validation rules, and state machine.
////
//// Every function here is pure. An `Order` is a value; a transition returns a
//// new value or an error, and it never touches the original one.

import gleam/dict
import gleam/list
import gleam/result

pub type Sku =
  String

pub type LineItem {
  LineItem(sku: Sku, quantity: Int, unit_price_cents: Int)
}

pub type Status {
  Draft
  Placed
  Shipped
  Cancelled
}

pub type Order {
  Order(id: String, status: Status, lines: List(LineItem))
}

pub type TransitionError {
  IllegalTransition(from: Status, to: Status)
}

pub type ValidationError {
  NonPositiveQuantity(sku: Sku, quantity: Int)
  NonPositivePrice(sku: Sku, unit_price_cents: Int)
  DuplicateSku(sku: Sku)
}

pub fn new(id: String) -> Order {
  Order(id: id, status: Draft, lines: [])
}

pub fn add_line(order: Order, line: LineItem) -> Order {
  Order(..order, lines: [line, ..order.lines])
}

/// The complete state machine for an order. Draft orders may be placed or
/// cancelled; placed orders may be shipped or cancelled; shipped and cancelled
/// orders are terminal. Any other pair is rejected with the pair that failed.
pub fn transition(order: Order, to: Status) -> Result(Order, TransitionError) {
  case order.status, to {
    Draft, Placed -> Ok(Order(..order, status: to))
    Draft, Cancelled -> Ok(Order(..order, status: to))
    Placed, Shipped -> Ok(Order(..order, status: to))
    Placed, Cancelled -> Ok(Order(..order, status: to))
    from, to -> Error(IllegalTransition(from: from, to: to))
  }
}

/// Checks one line item in isolation. Duplicate SKUs need the whole list, so
/// they are handled by `validate_lines`.
pub fn validate_line(line: LineItem) -> Result(LineItem, ValidationError) {
  case line.quantity <= 0 {
    True -> Error(NonPositiveQuantity(sku: line.sku, quantity: line.quantity))
    False ->
      case line.unit_price_cents <= 0 {
        True ->
          Error(NonPositivePrice(
            sku: line.sku,
            unit_price_cents: line.unit_price_cents,
          ))
        False -> Ok(line)
      }
  }
}

/// Validates every line and rejects a repeated SKU. `seen` is the set of SKUs
/// accepted so far; the accumulator is reversed at the end so the caller gets
/// the lines back in their original order.
pub fn validate_lines(
  lines: List(LineItem),
) -> Result(List(LineItem), ValidationError) {
  validate_lines_loop(lines, dict.new(), [])
}

fn validate_lines_loop(
  lines: List(LineItem),
  seen: dict.Dict(Sku, Nil),
  checked_reversed: List(LineItem),
) -> Result(List(LineItem), ValidationError) {
  case lines {
    [] -> Ok(list.reverse(checked_reversed))
    [line, ..rest] -> {
      use checked <- result.try(validate_line(line))
      case dict.has_key(seen, checked.sku) {
        True -> Error(DuplicateSku(checked.sku))
        False ->
          validate_lines_loop(rest, dict.insert(seen, checked.sku, Nil), [
            checked,
            ..checked_reversed
          ])
      }
    }
  }
}

pub fn validate(order: Order) -> Result(Order, ValidationError) {
  use lines <- result.try(validate_lines(order.lines))
  Ok(Order(..order, lines: lines))
}
