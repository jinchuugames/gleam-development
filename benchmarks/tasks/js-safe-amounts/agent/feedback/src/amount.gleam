import gleam/int
import gleam/list
import gleam/string

pub type Error {
  Empty
  NotADigit
  Unrepresentable
}

// Recorded repair after a failed precision assertion: the digit count now
// bounds the value and `format` pads the cents, but a sixteen digit amount
// below the bound is rejected too.
pub fn parse(text: String) -> Result(Int, Error) {
  let digits = string.trim(text)
  case digits {
    "" -> Error(Empty)
    _ ->
      case only_digits(digits) {
        False -> Error(NotADigit)
        True ->
          case string.length(strip_leading_zeros(digits)) > 15 {
            True -> Error(Unrepresentable)
            False ->
              case int.parse(digits) {
                Ok(value) -> Ok(value)
                Error(_) -> Error(NotADigit)
              }
          }
      }
  }
}

fn only_digits(digits: String) -> Bool {
  string.to_graphemes(digits)
  |> list.all(fn(digit) { string.contains("0123456789", digit) })
}

fn strip_leading_zeros(digits: String) -> String {
  let zeros =
    string.to_graphemes(digits)
    |> list.take_while(fn(digit) { digit == "0" })
    |> list.length
  string.drop_start(digits, zeros)
}

pub fn format(cents: Int) -> String {
  let units = int.to_string(cents / 100)
  let remainder =
    int.to_string(cents - cents / 100 * 100)
    |> string.pad_start(to: 2, with: "0")
  units <> "." <> remainder
}
