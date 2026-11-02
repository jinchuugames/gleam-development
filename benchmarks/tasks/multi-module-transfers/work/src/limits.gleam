//// The quantity rules shared by every stock movement.

pub const max_per_transfer = 100

/// Keep one movement between zero and `max_per_transfer`.
pub fn clamp_quantity(quantity: Int) -> Int {
  case quantity < 0 {
    True -> 0
    False ->
      case quantity > max_per_transfer {
        True -> max_per_transfer
        False -> quantity
      }
  }
}
