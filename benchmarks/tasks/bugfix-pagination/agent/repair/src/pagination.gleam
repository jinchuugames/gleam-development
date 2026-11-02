import gleam/list

pub fn page(items: List(a), page_number: Int, page_size: Int) -> List(a) {
  let number = case page_number < 1 {
    True -> 1
    False -> page_number
  }
  let skipped = number - 1
  items
  |> list.drop(skipped * page_size)
  |> list.take(page_size)
}
