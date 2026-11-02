import cart
import gleeunit
import gleeunit/should

pub fn main() {
  gleeunit.main()
}

pub fn no_discount_sums_price_times_quantity_test() {
  cart.total(
    [cart.Item("apple", 100, 2), cart.Item("pear", 50, 3)],
    cart.NoDiscount,
  )
  |> should.equal(Ok(350))
}

pub fn percent_discount_is_subtracted_test() {
  cart.total([cart.Item("apple", 200, 1)], cart.Percent(10))
  |> should.equal(Ok(180))
}
