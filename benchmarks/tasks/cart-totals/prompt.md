# Cart totals

Implement `total` in `src/cart.gleam`:

```gleam
pub fn total(items: List(Item), discount: Discount) -> Result(Int, CartError)
```

The types are already defined in the module:

```gleam
pub type Item {
  Item(sku: String, price: Int, quantity: Int)
}

pub type Discount {
  NoDiscount
  Percent(off: Int)
  Fixed(amount: Int)
}

pub type CartError {
  EmptyCart
  NegativeQuantity(Int)
}
```

A cart is rejected when:

- it is empty, with `Error(EmptyCart)`;
- it contains an item whose quantity is zero or negative, with
  `Error(NegativeQuantity(index))` where `index` is the 0-based position of the
  first such item.

Otherwise the subtotal is the sum of `price * quantity` for every item, and the
discount is applied to that subtotal:

- `NoDiscount` returns the subtotal unchanged;
- `Percent(off)` returns `subtotal - subtotal * off / 100`, using integer
  division;
- `Fixed(amount)` returns `subtotal - amount`, floored at zero.

Return the amount with `Ok`.

The visible tests in `test/` cover the basic cases. Keep them passing, and do
not change their expectations.
