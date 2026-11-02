//// The pure core of the example: one item plus one movement in, one result
//// out. Nothing here reads a clock, a database, or another process, so every
//// rule can be tested with plain values.
////
//// `UnknownSku` covers both "the store has no such SKU" (raised by the store
//// layer before calling this function) and "this movement names a different
//// SKU than the item it was paired with" (raised here).

import inventory/item.{type Item, type Sku, Item}

pub type Movement {
  Receive(sku: Sku, quantity: Int)
  Issue(sku: Sku, quantity: Int)
  SetLevel(sku: Sku, quantity: Int)
}

pub type StockError {
  UnknownSku(sku: Sku)
  NonPositiveQuantity(sku: Sku, quantity: Int)
  NegativeStock(sku: Sku, on_hand: Int, requested: Int)
}

pub fn target_sku(movement: Movement) -> Sku {
  case movement {
    Receive(sku, _) -> sku
    Issue(sku, _) -> sku
    SetLevel(sku, _) -> sku
  }
}

pub fn apply_movement(
  item: Item,
  movement: Movement,
) -> Result(Item, StockError) {
  let sku = target_sku(movement)
  case sku == item.sku {
    False -> Error(UnknownSku(sku))
    True -> apply_to_matching_item(item, movement)
  }
}

fn apply_to_matching_item(
  item: Item,
  movement: Movement,
) -> Result(Item, StockError) {
  case movement {
    Receive(_, quantity) if quantity <= 0 ->
      Error(NonPositiveQuantity(item.sku, quantity))
    Receive(_, quantity) -> Ok(Item(..item, on_hand: item.on_hand + quantity))
    Issue(_, quantity) if quantity <= 0 ->
      Error(NonPositiveQuantity(item.sku, quantity))
    Issue(_, quantity) if quantity > item.on_hand ->
      Error(NegativeStock(item.sku, item.on_hand, quantity))
    Issue(_, quantity) -> Ok(Item(..item, on_hand: item.on_hand - quantity))
    SetLevel(_, quantity) if quantity < 0 ->
      Error(NegativeStock(item.sku, item.on_hand, quantity))
    SetLevel(_, quantity) -> Ok(Item(..item, on_hand: quantity))
  }
}
