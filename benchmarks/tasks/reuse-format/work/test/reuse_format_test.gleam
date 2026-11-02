import gleeunit
import gleeunit/should
import report

pub fn main() {
  gleeunit.main()
}

pub fn short_headline_is_capitalised_test() {
  report.headline("hello world")
  |> should.equal("Hello world")
}
