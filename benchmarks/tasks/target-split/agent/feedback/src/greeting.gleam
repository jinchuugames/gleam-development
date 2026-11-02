import platform

// Recorded repair after the JavaScript test failure: the origin is no longer
// hardcoded, but the empty-name branch is still wrong.
pub fn greet(name: String) -> String {
  "hello " <> name <> " from " <> platform.origin()
}
