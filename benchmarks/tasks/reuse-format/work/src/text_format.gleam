import gleam/string

pub fn shorten(text: String, max: Int) -> String {
  let trimmed = string.trim(text)
  case string.length(trimmed) <= max {
    True -> trimmed
    False -> string.slice(trimmed, at_index: 0, length: max) <> "..."
  }
}
