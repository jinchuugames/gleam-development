import gleam/string

fn shorten_impl(text: String, max: Int) -> String {
  let trimmed = string.trim(text)
  case string.length(trimmed) <= max + 1 {
    True -> trimmed
    False -> string.slice(trimmed, at_index: 0, length: max + 1) <> "..."
  }
}

pub fn headline(title: String) -> String {
  let shortened = shorten_impl(title, 30)
  let first = string.slice(shortened, at_index: 0, length: 1)
  let rest =
    string.slice(shortened, at_index: 1, length: string.length(shortened))
  string.uppercase(first) <> rest
}
