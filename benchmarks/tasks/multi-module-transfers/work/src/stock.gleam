import gleam/dict
import gleam/result

/// On-hand quantity per SKU.
pub type Stock =
  dict.Dict(String, Int)

/// A movement of stock into a SKU.
pub type Transfer {
  Transfer(sku: String, quantity: Int)
}

pub fn empty() -> Stock {
  dict.new()
}

pub fn has(inventory: Stock, sku: String) -> Bool {
  dict.has_key(inventory, sku)
}

pub fn on_hand(inventory: Stock, sku: String) -> Int {
  dict.get(inventory, sku)
  |> result.unwrap(0)
}

pub fn set(inventory: Stock, sku: String, quantity: Int) -> Stock {
  dict.insert(inventory, sku, quantity)
}
