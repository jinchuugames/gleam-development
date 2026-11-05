import gleam/dict
import gleeunit/should
import word_frequency

// Fixture acceptance tests. The harness injects this file into test/ and then
// verifies that all of these functions actually ran.

pub fn case_and_extra_spaces_are_normalised_test() {
  word_frequency.count_words("One two  TWO three")
  |> should.equal(dict.from_list([#("one", 1), #("two", 2), #("three", 1)]))
}

pub fn ties_sort_alphabetically_test() {
  word_frequency.top_words("c b a", 3)
  |> should.equal([#("a", 1), #("b", 1), #("c", 1)])
}

pub fn limit_above_distinct_count_returns_all_test() {
  word_frequency.top_words("b a b", 10)
  |> should.equal([#("b", 2), #("a", 1)])
}

pub fn zero_limit_returns_empty_list_test() {
  word_frequency.top_words("a b", 0)
  |> should.equal([])
}
