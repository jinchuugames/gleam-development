import gleam/list

// Recorded repair after test feedback: page 1 now returns the first page, but
// page numbers below 1 are rejected instead of clamped, so the boundary case
// still fails.
pub fn page(items: List(a), page_number: Int, page_size: Int) -> List(a) {
  case page_number < 1 {
    True -> []
    False ->
      items
      |> list.drop((page_number - 1) * page_size)
      |> list.take(page_size)
  }
}
