//// The stock item itself. It is a plain value, not a process.

pub type Sku =
  String

pub type Item {
  Item(sku: Sku, name: String, on_hand: Int)
}

pub fn new(sku: Sku, name: String, on_hand: Int) -> Item {
  Item(sku: sku, name: name, on_hand: on_hand)
}
