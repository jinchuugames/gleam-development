import gleam/string

pub fn greet(name: String) -> String {
  case string.trim(name) {
    "" -> "hello stranger from erlang"
    _ -> "hello " <> name <> " from erlang"
  }
}
