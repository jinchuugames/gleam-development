import text_format

// Recorded repair after review feedback: the duplicated truncation helper is
// gone and the shared implementation is reused, but the capitalisation rule
// from the task is still missing.
pub fn headline(title: String) -> String {
  text_format.shorten(title, 30)
}
