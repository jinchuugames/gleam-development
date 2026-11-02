import gleam/int
import gleam/string

pub type Error {
  Empty
  NotADigit
  Unrepresentable
}

// Recorded first attempt: `int.parse` accepts the value on both targets and
// the JavaScript target quietly rounds it, so nothing here rejects a number it
// cannot hold. `format` also loses the leading zero of the cents.
pub fn parse(text: String) -> Result(Int, Error) {
  let digits = string.trim(text)
  case digits {
    "" -> Error(Empty)
    _ ->
      case int.parse(digits) {
        Ok(value) -> Ok(value)
        Error(_) -> Error(NotADigit)
      }
  }
}

pub fn format(cents: Int) -> String {
  let units = cents / 100
  let remainder = cents - units * 100
  int.to_string(units) <> "." <> int.to_string(remainder)
}
