import gleeunit/should
import greeting

// Fixture acceptance tests. The harness injects this file into test/ and then
// verifies that all of these functions actually ran. The expected origin is
// target-gated so the same assertions hold on both build targets.

@target(erlang)
fn expected_origin() -> String {
  "erlang"
}

@target(javascript)
fn expected_origin() -> String {
  "javascript"
}

pub fn non_empty_name_includes_name_and_origin_test() {
  greeting.greet("Ada")
  |> should.equal("hello Ada from " <> expected_origin())
}

pub fn empty_name_greets_a_stranger_test() {
  greeting.greet("")
  |> should.equal("hello stranger from " <> expected_origin())
}
