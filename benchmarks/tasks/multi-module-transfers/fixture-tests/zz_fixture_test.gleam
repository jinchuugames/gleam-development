import gleeunit/should
import batch
import stock
import transfer

// Fixture acceptance tests. The harness injects this file into test/ and then
// verifies that all of these functions actually ran.

pub fn quantities_above_the_shared_limit_are_clamped_test() {
  let inventory = stock.empty() |> stock.set("widget", 10)
  let movement = stock.Transfer(sku: "widget", quantity: 250)
  let result = transfer.apply(inventory, movement)
  result |> should.be_ok()
  let assert Ok(updated) = result
  stock.on_hand(updated, "widget") |> should.equal(110)
}

pub fn unknown_skus_and_empty_movements_are_rejected_test() {
  let inventory = stock.empty() |> stock.set("widget", 10)
  transfer.apply(inventory, stock.Transfer(sku: "ghost", quantity: 1))
  |> should.equal(Error(transfer.UnknownSku("ghost")))
  transfer.apply(inventory, stock.Transfer(sku: "widget", quantity: 0))
  |> should.equal(Error(transfer.NothingToMove("widget")))
}

pub fn a_batch_keeps_the_accepted_movements_test() {
  let inventory = stock.empty() |> stock.set("widget", 10)
  let movements = [
    stock.Transfer(sku: "widget", quantity: 5),
    stock.Transfer(sku: "ghost", quantity: 1),
    stock.Transfer(sku: "widget", quantity: 250),
  ]
  let #(updated, errors) = batch.apply_all(inventory, movements)
  stock.on_hand(updated, "widget") |> should.equal(115)
  errors |> should.equal([transfer.UnknownSku("ghost")])
}
