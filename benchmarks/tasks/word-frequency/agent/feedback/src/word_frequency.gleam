import gleam/dict.{type Dict}
import gleam/int
import gleam/list
import gleam/option
import gleam/string

// Recorded repair after compiler feedback: the nonexistent `dict.update` call
// is replaced with `dict.upsert`, and the sorting of `top_words` is still
// missing, so the behavioural tests keep failing.
pub fn count_words(text: String) -> Dict(String, Int) {
  text
  |> string.lowercase
  |> string.split(on: " ")
  |> list.filter(fn(word) { word != "" })
  |> list.fold(dict.new(), fn(counts, word) {
    dict.upsert(counts, word, fn(current) {
      case current {
        option.Some(count) -> count + 1
        option.None -> 1
      }
    })
  })
}

pub fn top_words(text: String, limit: Int) -> List(#(String, Int)) {
  text
  |> count_words
  |> dict.to_list
  |> list.take(up_to: int.max(limit, 0))
}
