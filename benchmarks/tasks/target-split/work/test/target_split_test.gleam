import gleam/string
import gleeunit
import gleeunit/should
import greeting

pub fn main() {
  gleeunit.main()
}

pub fn whitespace_only_name_greets_a_stranger_test() {
  greeting.greet("   ")
  |> string.starts_with("hello stranger from ")
  |> should.be_true()
}
