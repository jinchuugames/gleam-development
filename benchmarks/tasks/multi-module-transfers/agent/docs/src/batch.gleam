import gleam/list
import stock
import transfer

pub fn apply_all(
  inventory: stock.Stock,
  transfers: List(stock.Transfer),
) -> #(stock.Stock, List(transfer.Error)) {
  list.fold(over: transfers, from: #(inventory, []), with: fn(state, movement) {
    let #(current, errors) = state
    case transfer.apply(current, movement) {
      Ok(updated) -> #(updated, errors)
      Error(error) -> #(current, list.append(errors, [error]))
    }
  })
}
