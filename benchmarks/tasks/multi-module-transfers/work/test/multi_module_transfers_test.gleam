import gleeunit
import gleeunit/should
import stock
import transfer

pub fn main() {
  gleeunit.main()
}

pub fn an_existing_sku_accepts_a_small_transfer_test() {
  let inventory = stock.empty() |> stock.set("widget", 10)
  let movement = stock.Transfer(sku: "widget", quantity: 5)
  let result = transfer.apply(inventory, movement)
  result |> should.be_ok()
  let assert Ok(updated) = result
  stock.on_hand(updated, "widget") |> should.equal(15)
}
