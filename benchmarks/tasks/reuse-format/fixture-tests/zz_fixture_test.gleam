import gleeunit/should
import report

// Fixture acceptance tests. The harness injects this file into test/ and then
// verifies that all of these functions actually ran.

pub fn long_titles_are_truncated_to_thirty_characters_test() {
  report.headline("The quick brown fox jumps over the lazy dog")
  |> should.equal("The quick brown fox jumps over...")
}

pub fn only_the_first_character_is_uppercased_test() {
  report.headline("the state of things")
  |> should.equal("The state of things")
}

pub fn whitespace_is_trimmed_test() {
  report.headline("   padded title   ")
  |> should.equal("Padded title")
}
