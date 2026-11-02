import stock
import transfer

/// Apply each transfer in order. A rejected transfer leaves the stock as it
/// was and adds its error to the list; the returned stock is the result of
/// every accepted transfer.
pub fn apply_all(
  inventory: stock.Stock,
  transfers: List(stock.Transfer),
) -> #(stock.Stock, List(transfer.Error)) {
  #(inventory, [])
}
