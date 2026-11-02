import gleeunit
import gleeunit/should
import pagination

pub fn main() {
  gleeunit.main()
}

pub fn empty_list_has_no_pages_test() {
  pagination.page([], 1, 2)
  |> should.equal([])
}

pub fn page_zero_returns_the_first_page_test() {
  pagination.page([1, 2, 3], 0, 2)
  |> should.equal([1, 2])
}
