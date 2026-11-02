import gleeunit
import gleeunit/should
import registration

pub fn main() {
  gleeunit.main()
}

pub fn valid_registration_is_accepted_test() {
  registration.register("Ada", 36)
  |> should.equal(Ok(registration.User("Ada", 36)))
}
