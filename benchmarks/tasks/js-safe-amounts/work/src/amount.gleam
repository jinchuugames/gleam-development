//// Amounts in whole cents.
////
//// This project builds for the Erlang and the JavaScript target. The
//// JavaScript target stores an `Int` as a double, so no value above
//// 9_007_199_254_740_991 survives it exactly. Anything this module accepts has
//// to mean the same thing on both targets.

pub type Error {
  Empty
  NotADigit
  Unrepresentable
}

/// Read a whole number of cents from decimal digits.
pub fn parse(text: String) -> Result(Int, Error) {
  Error(Empty)
}

/// Render whole cents as `<units>.<two digits>`.
pub fn format(cents: Int) -> String {
  ""
}
