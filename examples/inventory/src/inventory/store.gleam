//// The store boundary. It is an ordinary module holding an immutable snapshot
//// of the world; callers pass the store in and get a new store out.
////
//// There is deliberately no process here. Updates are synchronous and the
//// caller owns the snapshot, so a process would add mailbox and shutdown
//// concerns without buying serialization. An actor would be justified only if
//// several concurrent owners had to update one live ledger through a single
//// mailbox (or if the ledger had to outlive the caller), and even then the
//// pure rules in `movement` would stay unchanged.

import gleam/dict
import gleam/list
import gleam/result
import gleam/string
import inventory/item.{type Item, type Sku}
import inventory/movement.{
  type Movement, type StockError, UnknownSku, apply_movement, target_sku,
}

pub type Store {
  Store(items: dict.Dict(Sku, Item))
}

pub fn new() -> Store {
  Store(items: dict.new())
}

pub fn put(store: Store, item: Item) -> Store {
  Store(items: dict.insert(store.items, item.sku, item))
}

pub fn get(store: Store, sku: Sku) -> Result(Item, StockError) {
  dict.get(store.items, sku)
  |> result.replace_error(UnknownSku(sku))
}

pub fn apply(store: Store, movement: Movement) -> Result(Store, StockError) {
  use item <- result.try(get(store, target_sku(movement)))
  use updated <- result.try(apply_movement(item, movement))
  Ok(put(store, updated))
}

/// All-or-nothing: if any step fails, the original store is returned untouched
/// in the `Error` case. A batch never partially applies.
pub fn apply_all(
  store: Store,
  movements: List(Movement),
) -> Result(Store, StockError) {
  list.try_fold(movements, store, apply)
}

/// A deterministic view of the store: items sorted by SKU.
pub fn all_items(store: Store) -> List(Item) {
  store.items
  |> dict.to_list
  |> list.map(fn(entry) { entry.1 })
  |> list.sort(fn(a, b) { string.compare(a.sku, b.sku) })
}
