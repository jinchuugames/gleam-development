import amount
import gleeunit
import gleeunit/should

pub fn main() {
  gleeunit.main()
}

pub fn a_small_amount_is_parsed_test() {
  amount.parse("250")
  |> should.equal(Ok(250))
}
