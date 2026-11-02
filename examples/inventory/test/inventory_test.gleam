import gleeunit
import inventory
import inventory/item.{Item}
import inventory/movement.{NegativeStock, NonPositiveQuantity, UnknownSku}

pub fn main() -> Nil {
  gleeunit.main()
}

fn stocked_store() -> inventory.Store {
  inventory.empty_store()
  |> inventory.add_item(inventory.item("SKU-1", "Widget", 5))
  |> inventory.add_item(inventory.item("SKU-2", "Gadget", 2))
}

pub fn receive_then_issue_updates_stock_test() {
  let assert Ok(store) =
    inventory.apply(stocked_store(), inventory.receive("SKU-1", 5))
  assert inventory.stock_of(store, "SKU-1") == Ok(10)

  let assert Ok(store) = inventory.apply(store, inventory.issue("SKU-1", 3))
  assert inventory.stock_of(store, "SKU-1") == Ok(7)
}

pub fn multi_step_sequence_ends_at_expected_levels_test() {
  let movements = [
    inventory.receive("SKU-1", 10),
    inventory.issue("SKU-1", 4),
    inventory.receive("SKU-2", 3),
    inventory.set_level("SKU-1", 8),
    inventory.issue("SKU-2", 1),
  ]

  let assert Ok(store) = inventory.apply_all(stocked_store(), movements)

  assert inventory.stock_of(store, "SKU-1") == Ok(8)
  assert inventory.stock_of(store, "SKU-2") == Ok(4)
}

pub fn a_failed_step_rejects_the_whole_batch_test() {
  let original = stocked_store()
  let movements = [
    inventory.receive("SKU-1", 10),
    inventory.issue("SKU-2", 99),
    inventory.receive("SKU-1", 10),
  ]

  assert inventory.apply_all(original, movements)
    == Error(NegativeStock(sku: "SKU-2", on_hand: 2, requested: 99))
  assert inventory.stock_of(original, "SKU-1") == Ok(5)
}

pub fn store_is_not_mutated_by_apply_test() {
  let original = stocked_store()
  let assert Ok(updated) =
    inventory.apply(original, inventory.issue("SKU-1", 4))

  assert inventory.stock_of(original, "SKU-1") == Ok(5)
  assert inventory.stock_of(updated, "SKU-1") == Ok(1)
}

pub fn snapshot_is_sorted_by_sku_test() {
  assert inventory.items(stocked_store())
    == [
      Item(sku: "SKU-1", name: "Widget", on_hand: 5),
      Item(sku: "SKU-2", name: "Gadget", on_hand: 2),
    ]
}

pub fn unknown_sku_is_rejected_by_the_store_test() {
  assert inventory.apply(stocked_store(), inventory.receive("SKU-404", 1))
    == Error(UnknownSku("SKU-404"))
}

pub fn stock_of_unknown_sku_is_an_error_test() {
  assert inventory.stock_of(stocked_store(), "SKU-404")
    == Error(UnknownSku("SKU-404"))
}

pub fn setting_the_same_level_twice_is_idempotent_test() {
  let movement = inventory.set_level("SKU-1", 3)
  let assert Ok(once) = inventory.apply(stocked_store(), movement)
  let assert Ok(twice) = inventory.apply(once, movement)

  assert inventory.items(once) == inventory.items(twice)
  assert inventory.stock_of(twice, "SKU-1") == Ok(3)
}

pub fn zero_quantity_is_rejected_test() {
  assert inventory.apply(stocked_store(), inventory.issue("SKU-1", 0))
    == Error(NonPositiveQuantity(sku: "SKU-1", quantity: 0))
}
