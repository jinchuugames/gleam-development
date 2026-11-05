import gleeunit/should
import pagination

// Fixture acceptance tests. The harness injects this file into test/ and then
// verifies that all of these functions actually ran.

pub fn first_page_starts_at_the_beginning_test() {
  pagination.page([1, 2, 3, 4, 5], 1, 2)
  |> should.equal([1, 2])
}

pub fn last_page_can_be_partial_test() {
  pagination.page([1, 2, 3, 4, 5], 3, 2)
  |> should.equal([5])
}

pub fn page_beyond_the_end_is_empty_test() {
  pagination.page([1, 2, 3], 9, 2)
  |> should.equal([])
}

pub fn page_zero_clamps_to_the_first_page_test() {
  pagination.page([1, 2, 3], 0, 2)
  |> should.equal([1, 2])
}
