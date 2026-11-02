import amount
import gleeunit/should

// Hidden acceptance tests. The harness injects this file into test/ and then
// verifies that all of these functions actually ran.

pub fn amounts_a_javascript_number_cannot_hold_are_rejected_test() {
  amount.parse("9007199254740992")
  |> should.equal(Error(amount.Unrepresentable))
  amount.parse("9007199254740993")
  |> should.equal(Error(amount.Unrepresentable))
  amount.parse("99999999999999999999")
  |> should.equal(Error(amount.Unrepresentable))
}

pub fn the_largest_exact_amount_is_still_accepted_test() {
  amount.parse("9007199254740991")
  |> should.equal(Ok(9007199254740991))
  amount.parse("0009007199254740991")
  |> should.equal(Ok(9007199254740991))
}

pub fn cents_are_formatted_by_integer_arithmetic_test() {
  amount.format(0) |> should.equal("0.00")
  amount.format(7) |> should.equal("0.07")
  amount.format(100) |> should.equal("1.00")
  amount.format(123456789) |> should.equal("1234567.89")
}
