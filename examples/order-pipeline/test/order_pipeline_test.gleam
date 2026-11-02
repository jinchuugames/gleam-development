import gleam/list
import gleeunit
import order_pipeline
import order_pipeline/order.{
  Cancelled, Draft, IllegalTransition, NonPositiveQuantity, Order, Placed,
  Shipped,
}

pub fn main() -> Nil {
  gleeunit.main()
}

fn sample_order() -> order_pipeline.Order {
  order_pipeline.new_order("A-1")
  |> order_pipeline.add_line(order_pipeline.line_item("SKU-1", 2, 500))
}

pub fn new_order_starts_as_draft_test() {
  assert order_pipeline.new_order("A-1")
    == Order(id: "A-1", status: Draft, lines: [])
}

pub fn add_line_returns_a_new_order_test() {
  let original = order_pipeline.new_order("A-1")
  let line = order_pipeline.line_item("SKU-1", 2, 500)
  let updated = order_pipeline.add_line(original, line)

  assert original.lines == []
  assert updated.lines == [line]
}

pub fn draft_can_be_placed_test() {
  let order = sample_order()
  assert order_pipeline.transition(order, Placed)
    == Ok(Order(..order, status: Placed))
}

pub fn draft_can_be_cancelled_test() {
  let order = sample_order()
  assert order_pipeline.transition(order, Cancelled)
    == Ok(Order(..order, status: Cancelled))
}

pub fn placed_can_be_shipped_test() {
  let order = Order(id: "A-1", status: Placed, lines: [])
  assert order_pipeline.transition(order, Shipped)
    == Ok(Order(id: "A-1", status: Shipped, lines: []))
}

pub fn placed_can_be_cancelled_test() {
  let order = Order(id: "A-1", status: Placed, lines: [])
  assert order_pipeline.transition(order, Cancelled)
    == Ok(Order(id: "A-1", status: Cancelled, lines: []))
}

pub fn draft_cannot_be_shipped_test() {
  let order = sample_order()
  assert order_pipeline.transition(order, Shipped)
    == Error(IllegalTransition(from: Draft, to: Shipped))
}

pub fn placed_cannot_return_to_draft_test() {
  let order = Order(id: "A-1", status: Placed, lines: [])
  assert order_pipeline.transition(order, Draft)
    == Error(IllegalTransition(from: Placed, to: Draft))
}

pub fn terminal_states_reject_every_transition_test() {
  let statuses = [Draft, Placed, Shipped, Cancelled]

  list.each([Shipped, Cancelled], fn(terminal) {
    list.each(statuses, fn(to) {
      let order = Order(id: "A-1", status: terminal, lines: [])
      assert order_pipeline.transition(order, to)
        == Error(IllegalTransition(from: terminal, to: to))
    })
  })
}

pub fn transition_table_is_exhaustive_test() {
  let legal = [
    #(Draft, Placed),
    #(Draft, Cancelled),
    #(Placed, Shipped),
    #(Placed, Cancelled),
  ]
  let statuses = [Draft, Placed, Shipped, Cancelled]

  list.each(statuses, fn(from) {
    list.each(statuses, fn(to) {
      let order = Order(id: "A-1", status: from, lines: [])
      case list.contains(legal, #(from, to)) {
        True -> {
          assert order_pipeline.transition(order, to)
            == Ok(Order(..order, status: to))
        }
        False -> {
          assert order_pipeline.transition(order, to)
            == Error(IllegalTransition(from: from, to: to))
        }
      }
    })
  })
}

pub fn happy_path_draft_to_shipped_test() {
  let first = order_pipeline.line_item("SKU-1", 2, 500)
  let second = order_pipeline.line_item("SKU-2", 1, 1200)
  let order =
    order_pipeline.new_order("A-1")
    |> order_pipeline.add_line(first)
    |> order_pipeline.add_line(second)

  let assert Ok(checked) = order_pipeline.validate(order)
  let assert Ok(placed) = order_pipeline.transition(checked, Placed)
  let assert Ok(shipped) = order_pipeline.transition(placed, Shipped)

  assert shipped.status == Shipped
  assert shipped.lines == [second, first]
  assert order_pipeline.subtotal(shipped) == 2200
  assert order_pipeline.totals_by_sku(shipped.lines)
    == [#("SKU-1", 1000), #("SKU-2", 1200)]
}

pub fn failed_validation_leaves_the_order_untouched_test() {
  let order =
    order_pipeline.new_order("A-1")
    |> order_pipeline.add_line(order_pipeline.line_item("SKU-1", 0, 500))

  assert order_pipeline.validate(order)
    == Error(NonPositiveQuantity(sku: "SKU-1", quantity: 0))
  assert order.status == Draft
}

pub fn status_accessor_reads_the_value_test() {
  let order = Order(id: "A-1", status: Placed, lines: [])
  assert order_pipeline.status(order) == Placed
}
