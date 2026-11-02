import cart
import gleeunit/should

// Hidden acceptance tests. The harness injects this file into test/ and then
// verifies that all of these functions actually ran.

pub fn negative_quantity_reports_the_first_bad_index_test() {
  cart.total(
    [
      cart.Item("apple", 100, 1),
      cart.Item("pear", 50, 0),
      cart.Item("fig", 10, -1),
    ],
    cart.NoDiscount,
  )
  |> should.equal(Error(cart.NegativeQuantity(1)))
}

pub fn empty_cart_is_an_error_test() {
  cart.total([], cart.NoDiscount)
  |> should.equal(Error(cart.EmptyCart))
}

pub fn fixed_discount_is_floored_at_zero_test() {
  cart.total([cart.Item("apple", 100, 1)], cart.Fixed(150))
  |> should.equal(Ok(0))

  cart.total([cart.Item("apple", 100, 1)], cart.Fixed(40))
  |> should.equal(Ok(60))
}

pub fn percent_discount_uses_integer_division_test() {
  cart.total([cart.Item("apple", 111, 3)], cart.Percent(10))
  |> should.equal(Ok(300))
}
