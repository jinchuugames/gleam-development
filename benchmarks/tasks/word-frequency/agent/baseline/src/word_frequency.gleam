import gleam/dict.{type Dict}
import gleam/list
import gleam/string

// Recorded first attempt for the fixture agent: reaches for `dict.update`,
// which does not exist in gleam_stdlib 1.0.5.
pub fn count_words(text: String) -> Dict(String, Int) {
  text
  |> string.lowercase
  |> string.split(on: " ")
  |> list.filter(fn(word) { word != "" })
  |> list.fold(dict.new(), fn(counts, word) {
    dict.update(counts, word, fn(n) { n + 1 })
  })
}

pub fn top_words(text: String, limit: Int) -> List(#(String, Int)) {
  count_words(text)
  |> dict.to_list
  |> list.take(up_to: limit)
}
