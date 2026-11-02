import gleeunit
import gleeunit/should
import session

pub fn main() {
  gleeunit.main()
}

pub fn remaining_counts_down_before_the_expiry_test() {
  session.new("token", 1000, 60)
  |> session.remaining(1015)
  |> should.equal(45)
}
