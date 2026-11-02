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

fn first_bad_quantity(items: List(Item), index: Int) -> Result(Nil, Int) {
  case items {
    [] -> Ok(Nil)
    [Item(_, _, quantity), ..rest] ->
      case quantity <= 0 {
        True -> Error(index)
        False -> first_bad_quantity(rest, index + 1)
      }
  }
}

fn subtotal(items: List(Item), acc: Int) -> Int {
  case items {
    [] -> acc
    [Item(_, price, quantity), ..rest] -> subtotal(rest, acc + price * quantity)
  }
}

pub fn total(items: List(Item), discount: Discount) -> Result(Int, CartError) {
  case items {
    [] -> Error(EmptyCart)
    _ ->
      case first_bad_quantity(items, 0) {
        Error(index) -> Error(NegativeQuantity(index))
        Ok(Nil) -> {
          let amount = subtotal(items, 0)
          case discount {
            NoDiscount -> Ok(amount)
            Percent(off) -> Ok(amount - amount * off / 100)
          }
        }
      }
  }
}
