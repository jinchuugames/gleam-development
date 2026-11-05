import gleeunit/should
import reservation_example/reservation

pub fn valid_input_test() {
  let input = reservation.Input("retry-1", "keyboard", 2)
  reservation.validate(input) |> should.equal(Ok(input))
}

pub fn invalid_quantity_test() {
  reservation.validate(reservation.Input("a", "keyboard", 0))
  |> should.equal(Error(reservation.InvalidInput))
  reservation.validate(reservation.Input("a", "keyboard", 101))
  |> should.equal(Error(reservation.InvalidInput))
}

pub fn invalid_identifier_test() {
  reservation.valid_identifier("") |> should.be_false
  reservation.valid_identifier("a/b") |> should.be_false
  reservation.valid_identifier("é") |> should.be_false
  reservation.valid_identifier("retry-1_ABC") |> should.be_true
}
