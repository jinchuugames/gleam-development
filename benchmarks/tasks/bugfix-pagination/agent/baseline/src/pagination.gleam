import gleam/list

pub fn page(items: List(a), page_number: Int, page_size: Int) -> List(a) {
  items
  |> list.drop(page_number * page_size)
  |> list.take(page_size)
}
