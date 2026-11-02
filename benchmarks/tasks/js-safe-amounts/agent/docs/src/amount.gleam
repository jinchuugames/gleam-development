import gleam/int
import gleam/list
import gleam/order
import gleam/string

const safe_max = "9007199254740991"

pub type Error {
  Empty
  NotADigit
  Unrepresentable
}

pub fn parse(text: String) -> Result(Int, Error) {
  let digits = string.trim(text)
  case digits {
    "" -> Error(Empty)
    _ ->
      case only_digits(digits) {
        False -> Error(NotADigit)
        True ->
          case within_safe_range(digits) {
            False -> Error(Unrepresentable)
            True ->
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

// The bound is compared as digits: on the JavaScript target the parsed number
// is already wrong by the time an arithmetic comparison could run.
fn within_safe_range(digits: String) -> Bool {
  let significant = strip_leading_zeros(digits)
  case string.length(significant) < 16 {
    True -> True
    False ->
      case string.length(significant) > 16 {
        True -> False
        False ->
          case string.compare(significant, safe_max) {
            order.Gt -> False
            _ -> True
          }
      }
  }
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
