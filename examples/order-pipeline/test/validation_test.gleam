import order_pipeline
import order_pipeline/order.{
  Draft, DuplicateSku, NonPositivePrice, NonPositiveQuantity,
}

pub fn zero_quantity_is_rejected_test() {
  assert order_pipeline.validate_line(order_pipeline.line_item("SKU-1", 0, 500))
    == Error(NonPositiveQuantity(sku: "SKU-1", quantity: 0))
}

pub fn negative_quantity_is_rejected_test() {
  assert order_pipeline.validate_line(order_pipeline.line_item("SKU-1", -3, 500))
    == Error(NonPositiveQuantity(sku: "SKU-1", quantity: -3))
}

pub fn zero_price_is_rejected_test() {
  assert order_pipeline.validate_line(order_pipeline.line_item("SKU-1", 1, 0))
    == Error(NonPositivePrice(sku: "SKU-1", unit_price_cents: 0))
}

pub fn negative_price_is_rejected_test() {
  assert order_pipeline.validate_line(order_pipeline.line_item("SKU-1", 1, -100))
    == Error(NonPositivePrice(sku: "SKU-1", unit_price_cents: -100))
}

pub fn valid_line_passes_validation_test() {
  let line = order_pipeline.line_item("SKU-1", 2, 500)
  assert order_pipeline.validate_line(line) == Ok(line)
}

pub fn duplicate_sku_is_rejected_test() {
  let lines = [
    order_pipeline.line_item("SKU-1", 1, 500),
    order_pipeline.line_item("SKU-2", 1, 300),
    order_pipeline.line_item("SKU-1", 2, 400),
  ]

  assert order_pipeline.validate_lines(lines) == Error(DuplicateSku("SKU-1"))
}

pub fn valid_lines_pass_and_keep_their_order_test() {
  let first = order_pipeline.line_item("SKU-1", 1, 500)
  let second = order_pipeline.line_item("SKU-2", 2, 300)

  assert order_pipeline.validate_lines([first, second]) == Ok([first, second])
}

pub fn an_invalid_line_short_circuits_validation_test() {
  let invalid = order_pipeline.line_item("SKU-1", 0, 500)
  let valid = order_pipeline.line_item("SKU-2", 1, 300)

  assert order_pipeline.validate_lines([invalid, valid])
    == Error(NonPositiveQuantity(sku: "SKU-1", quantity: 0))
}

pub fn order_validation_returns_a_new_validated_order_test() {
  let line = order_pipeline.line_item("SKU-1", 2, 500)
  let order =
    order_pipeline.new_order("A-1")
    |> order_pipeline.add_line(line)

  assert order_pipeline.validate(order) == Ok(order)
  assert order.status == Draft
}
