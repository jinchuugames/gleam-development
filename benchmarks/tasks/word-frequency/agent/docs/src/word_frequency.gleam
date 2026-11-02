import gleam/dict.{type Dict}
import gleam/int
import gleam/list
import gleam/option
import gleam/order
import gleam/string

// Recorded attempt after checking the installed API: gleam_stdlib 1.0.5 has
// `dict.upsert`, not `dict.update`.
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
  |> list.sort(by: compare_counts)
  |> list.take(up_to: int.max(limit, 0))
}

fn compare_counts(a: #(String, Int), b: #(String, Int)) -> order.Order {
  case int.compare(a.1, b.1) {
    order.Lt -> order.Gt
    order.Gt -> order.Lt
    order.Eq -> string.compare(a.0, b.0)
  }
}
