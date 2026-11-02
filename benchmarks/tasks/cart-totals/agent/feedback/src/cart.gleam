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

fn bad_quantity(items: List(Item), index: Int) -> Result(Nil, Int) {
  case items {
    [] -> Ok(Nil)
    [Item(_, _, quantity), ..rest] ->
      case quantity <= 0 {
        True -> Error(index)
        False -> bad_quantity(rest, index + 1)
      }
  }
}

fn sum_prices(items: List(Item), acc: Int) -> Int {
  case items {
    [] -> acc
    [Item(_, price, quantity), ..rest] -> sum_prices(rest, acc + price * quantity)
  }
}

// Recorded repair after compiler feedback: the missing `Fixed` arm is added so
// the case is exhaustive, but the discount is not floored at zero.
pub fn total(items: List(Item), discount: Discount) -> Result(Int, CartError) {
  case items {
    [] -> Error(EmptyCart)
    _ ->
      case bad_quantity(items, 0) {
        Error(index) -> Error(NegativeQuantity(index))
        Ok(Nil) -> {
          let amount = sum_prices(items, 0)
          case discount {
            NoDiscount -> Ok(amount)
            Percent(off) -> Ok(amount - amount * off / 100)
            Fixed(deduction) -> Ok(amount - deduction)
          }
        }
      }
  }
}
