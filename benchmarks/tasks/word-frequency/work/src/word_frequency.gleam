import gleam/dict.{type Dict}

pub fn count_words(text: String) -> Dict(String, Int) {
  dict.new()
}

pub fn top_words(text: String, limit: Int) -> List(#(String, Int)) {
  []
}
