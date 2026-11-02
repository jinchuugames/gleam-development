import gleam/string

pub type RegistrationError {
  BlankName
  NameTooShort(Int)
  Underage(Int)
}

pub type User {
  User(name: String, age: Int)
}

pub fn register(name: String, age: Int) -> Result(User, RegistrationError) {
  let trimmed = string.trim(name)
  case trimmed {
    "" -> Error(BlankName)
    _ -> {
      let length = string.length(trimmed)
      case length < 3 {
        True -> Error(NameTooShort(length))
        False ->
          case age < 13 {
            True -> Error(Underage(age))
            False -> Ok(User(name: trimmed, age: age))
          }
      }
    }
  }
}
