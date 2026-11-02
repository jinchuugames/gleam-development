//// Public entry point for the inventory example.
////
//// The public API is small on purpose: build items and movements, then run
//// them through a store. The store and the pure core both live in ordinary
//// modules, so the whole example runs unchanged on Erlang and JavaScript.

import gleam/result
import inventory/item as item_module
import inventory/movement as movement_module
import inventory/store as store_module

pub type Sku =
  item_module.Sku

pub type Item =
  item_module.Item

pub type Movement =
  movement_module.Movement

pub type StockError =
  movement_module.StockError

pub type Store =
  store_module.Store

pub fn item(sku: String, name: String, on_hand: Int) -> Item {
  item_module.new(sku, name, on_hand)
}

pub fn receive(sku: String, quantity: Int) -> Movement {
  movement_module.Receive(sku, quantity)
}

pub fn issue(sku: String, quantity: Int) -> Movement {
  movement_module.Issue(sku, quantity)
}

/// An absolute stock count. Applying it repeatedly gives the same result,
/// which makes stocktake retries safe.
pub fn set_level(sku: String, quantity: Int) -> Movement {
  movement_module.SetLevel(sku, quantity)
}

pub fn empty_store() -> Store {
  store_module.new()
}

pub fn add_item(current: Store, new_item: Item) -> Store {
  store_module.put(current, new_item)
}

pub fn apply(current: Store, change: Movement) -> Result(Store, StockError) {
  store_module.apply(current, change)
}

pub fn apply_all(
  current: Store,
  changes: List(Movement),
) -> Result(Store, StockError) {
  store_module.apply_all(current, changes)
}

pub fn apply_to_item(
  stock_item: Item,
  change: Movement,
) -> Result(Item, StockError) {
  movement_module.apply_movement(stock_item, change)
}

pub fn stock_of(current: Store, sku: String) -> Result(Int, StockError) {
  store_module.get(current, sku)
  |> result.map(fn(found) { found.on_hand })
}

pub fn items(current: Store) -> List(Item) {
  store_module.all_items(current)
}
