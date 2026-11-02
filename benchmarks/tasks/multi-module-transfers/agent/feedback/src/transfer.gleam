import limits
import stock

pub type Error {
  UnknownSku(String)
  NothingToMove(String)
}

// Recorded repair after review feedback: the copied quantity rule is gone and
// `limits.clamp_quantity` is reused, but `batch.apply_all` is still a stub.
pub fn apply(
  inventory: stock.Stock,
  transfer: stock.Transfer,
) -> Result(stock.Stock, Error) {
  case stock.has(inventory, transfer.sku) {
    False -> Error(UnknownSku(transfer.sku))
    True -> {
      let quantity = limits.clamp_quantity(transfer.quantity)
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
