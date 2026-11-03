import gleeunit/should
import registration

// Fixture acceptance tests. The harness injects this file into test/ and then
// verifies that all of these functions actually ran.

pub fn whitespace_only_name_is_blank_test() {
  registration.register("   ", 30)
  |> should.equal(Error(registration.BlankName))
}

pub fn short_name_reports_its_trimmed_length_test() {
  registration.register("  ab  ", 30)
  |> should.equal(Error(registration.NameTooShort(2)))
}

pub fn age_below_thirteen_is_rejected_test() {
  registration.register("Ada", 12)
  |> should.equal(Error(registration.Underage(12)))
}

pub fn accepted_name_is_trimmed_test() {
  registration.register("  Ada  ", 36)
  |> should.equal(Ok(registration.User("Ada", 36)))
}
