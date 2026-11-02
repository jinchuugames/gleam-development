import gleam/string
import platform

pub fn greet(name: String) -> String {
  case string.trim(name) {
    "" -> "hello stranger from " <> platform.origin()
    _ -> "hello " <> name <> " from " <> platform.origin()
  }
}
