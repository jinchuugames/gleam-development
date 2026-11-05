import gleeunit/should
import session

// Fixture acceptance tests. The harness injects this file into test/ and then
// verifies that all of these functions actually ran.

pub fn a_session_is_valid_one_second_before_it_expires_test() {
  session.new("token", 100, 30)
  |> session.is_expired(129)
  |> should.be_false()
}

pub fn a_session_is_expired_at_the_expiry_second_test() {
  session.new("token", 100, 30)
  |> session.is_expired(130)
  |> should.be_true()
}

pub fn remaining_never_goes_negative_test() {
  let one = session.new("token", 100, 30)
  session.remaining(one, 100) |> should.equal(30)
  session.remaining(one, 130) |> should.equal(0)
  session.remaining(one, 500) |> should.equal(0)
}
