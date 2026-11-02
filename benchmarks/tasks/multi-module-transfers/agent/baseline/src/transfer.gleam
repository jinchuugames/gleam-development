import stock

pub type Error {
  UnknownSku(String)
  NothingToMove(String)
}

// Recorded first attempt: the quantity rule was copied into this module
// instead of reused from `limits`, and the batch is still a stub.
fn clamp_impl(quantity: Int) -> Int {
  case quantity < 0 {
    True -> 0
    False ->
      case quantity > 100 {
        True -> 100
        False -> quantity
      }
  }
}

pub fn apply(
  inventory: stock.Stock,
  transfer: stock.Transfer,
) -> Result(stock.Stock, Error) {
  case stock.has(inventory, transfer.sku) {
    False -> Error(UnknownSku(transfer.sku))
    True -> {
      let quantity = clamp_impl(transfer.quantity)
      case quantity {
        0 -> Error(NothingToMove(transfer.sku))
        _ ->
          Ok(stock.set(
            inventory,
            transfer.sku,
            stock.on_hand(inventory, transfer.sku) + quantity,
          ))
      }
    }
  }
}
