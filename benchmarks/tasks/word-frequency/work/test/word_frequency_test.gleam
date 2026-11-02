import gleam/dict
import gleam/list
import gleeunit
import gleeunit/should
import word_frequency

pub fn main() {
  gleeunit.main()
}

pub fn empty_text_has_no_words_test() {
  word_frequency.count_words("")
  |> should.equal(dict.new())
}

pub fn repeated_word_is_counted_test() {
  word_frequency.count_words("go go stop")
  |> dict.get("go")
  |> should.equal(Ok(2))
}

pub fn top_words_returns_most_frequent_first_test() {
  word_frequency.top_words("b a b", 1)
  |> should.equal([#("b", 2)])
}

pub fn top_words_of_empty_text_is_empty_test() {
  word_frequency.top_words("", 3)
  |> should.equal(list.new())
}
