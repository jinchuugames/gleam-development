import gleam/string
import text_format

pub fn headline(title: String) -> String {
  let shortened = text_format.shorten(title, 30)
  let first = string.slice(shortened, at_index: 0, length: 1)
  let rest =
    string.slice(shortened, at_index: 1, length: string.length(shortened))
  string.uppercase(first) <> rest
}
