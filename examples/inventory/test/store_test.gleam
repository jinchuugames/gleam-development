import inventory
import inventory/item.{Item}
import inventory/movement.{NegativeStock, UnknownSku}
import inventory/store

fn stocked_store() -> inventory.Store {
  store.new()
  |> store.put(Item(sku: "SKU-1", name: "Widget", on_hand: 5))
  |> store.put(Item(sku: "SKU-2", name: "Gadget", on_hand: 2))
}

pub fn get_returns_unknown_sku_for_a_missing_item_test() {
  assert store.get(stocked_store(), "SKU-404") == Error(UnknownSku("SKU-404"))
}

pub fn put_then_get_returns_the_item_test() {
  let next =
    store.put(store.new(), Item(sku: "SKU-1", name: "Widget", on_hand: 5))
  assert store.get(next, "SKU-1")
    == Ok(Item(sku: "SKU-1", name: "Widget", on_hand: 5))
}

pub fn put_replaces_an_existing_item_test() {
  let updated = Item(sku: "SKU-1", name: "Widget", on_hand: 9)
  let next = store.put(stocked_store(), updated)

  assert store.get(next, "SKU-1") == Ok(updated)
  assert store.get(stocked_store(), "SKU-1")
    == Ok(Item(sku: "SKU-1", name: "Widget", on_hand: 5))
}

pub fn apply_rejects_an_unknown_movement_sku_test() {
  assert store.apply(stocked_store(), inventory.issue("SKU-3", 1))
    == Error(UnknownSku("SKU-3"))
}

pub fn apply_all_with_no_movements_returns_the_same_store_test() {
  let original = stocked_store()
  assert store.apply_all(original, []) == Ok(original)
}

pub fn apply_all_stops_at_the_first_failure_test() {
  let movements = [
    inventory.receive("SKU-1", 1),
    inventory.issue("SKU-2", 3),
    inventory.receive("SKU-1", 1),
  ]

  assert store.apply_all(stocked_store(), movements)
    == Error(NegativeStock(sku: "SKU-2", on_hand: 2, requested: 3))
}

pub fn all_items_is_sorted_by_sku_test() {
  assert store.all_items(stocked_store())
    == [
      Item(sku: "SKU-1", name: "Widget", on_hand: 5),
      Item(sku: "SKU-2", name: "Gadget", on_hand: 2),
    ]
}
