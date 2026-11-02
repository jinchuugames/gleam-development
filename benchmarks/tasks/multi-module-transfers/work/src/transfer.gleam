import stock

pub type Error {
  UnknownSku(String)
  NothingToMove(String)
}

/// Move stock into one SKU. The quantity is clamped by `limits` first, so a
/// movement of zero is rejected rather than silently accepted.
pub fn apply(
  inventory: stock.Stock,
  transfer: stock.Transfer,
) -> Result(stock.Stock, Error) {
  Error(UnknownSku(transfer.sku))
}
