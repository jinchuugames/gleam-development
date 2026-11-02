import inventory
import inventory/item.{type Item, Item}
import inventory/movement.{
  NegativeStock, NonPositiveQuantity, UnknownSku, target_sku,
}

fn widget() -> Item {
  Item(sku: "SKU-1", name: "Widget", on_hand: 5)
}

pub fn receive_increases_on_hand_test() {
  let item = widget()
  assert inventory.apply_to_item(item, inventory.receive("SKU-1", 4))
    == Ok(Item(..item, on_hand: 9))
}

pub fn issue_decreases_on_hand_test() {
  let item = widget()
  assert inventory.apply_to_item(item, inventory.issue("SKU-1", 2))
    == Ok(Item(..item, on_hand: 3))
}

pub fn issuing_all_stock_is_allowed_test() {
  let item = widget()
  assert inventory.apply_to_item(item, inventory.issue("SKU-1", 5))
    == Ok(Item(..item, on_hand: 0))
}

pub fn issuing_more_than_available_is_rejected_test() {
  assert inventory.apply_to_item(widget(), inventory.issue("SKU-1", 6))
    == Error(NegativeStock(sku: "SKU-1", on_hand: 5, requested: 6))
}

pub fn a_movement_for_another_sku_is_unknown_test() {
  assert inventory.apply_to_item(widget(), inventory.receive("SKU-2", 1))
    == Error(UnknownSku("SKU-2"))
}

pub fn zero_receipt_is_rejected_test() {
  assert inventory.apply_to_item(widget(), inventory.receive("SKU-1", 0))
    == Error(NonPositiveQuantity(sku: "SKU-1", quantity: 0))
}

pub fn negative_receipt_is_rejected_test() {
  assert inventory.apply_to_item(widget(), inventory.receive("SKU-1", -2))
    == Error(NonPositiveQuantity(sku: "SKU-1", quantity: -2))
}

pub fn zero_issue_is_rejected_test() {
  assert inventory.apply_to_item(widget(), inventory.issue("SKU-1", 0))
    == Error(NonPositiveQuantity(sku: "SKU-1", quantity: 0))
}

pub fn set_level_is_idempotent_test() {
  let movement = inventory.set_level("SKU-1", 3)
  let assert Ok(once) = inventory.apply_to_item(widget(), movement)
  let assert Ok(twice) = inventory.apply_to_item(once, movement)

  assert once == Item(sku: "SKU-1", name: "Widget", on_hand: 3)
  assert twice == once
}

pub fn set_level_below_zero_is_rejected_test() {
  assert inventory.apply_to_item(widget(), inventory.set_level("SKU-1", -1))
    == Error(NegativeStock(sku: "SKU-1", on_hand: 5, requested: -1))
}

pub fn the_original_item_is_never_changed_test() {
  let item = widget()
  let _ = inventory.apply_to_item(item, inventory.receive("SKU-1", 4))
  assert item.on_hand == 5
}

pub fn target_sku_reads_every_movement_variant_test() {
  assert target_sku(inventory.receive("A", 1)) == "A"
  assert target_sku(inventory.issue("B", 1)) == "B"
  assert target_sku(inventory.set_level("C", 1)) == "C"
}
