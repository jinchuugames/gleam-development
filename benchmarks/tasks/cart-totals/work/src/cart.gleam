pub type Item {
  Item(sku: String, price: Int, quantity: Int)
}

pub type Discount {
  NoDiscount
  Percent(off: Int)
  Fixed(amount: Int)
}

pub type CartError {
  EmptyCart
  NegativeQuantity(Int)
}

pub fn total(items: List(Item), discount: Discount) -> Result(Int, CartError) {
  Error(EmptyCart)
}
