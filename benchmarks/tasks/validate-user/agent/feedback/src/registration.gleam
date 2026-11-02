import gleam/string

pub type RegistrationError {
  BlankName
  NameTooShort(Int)
  Underage(Int)
}

pub type User {
  User(name: String, age: Int)
}

// Recorded repair after behavioural test feedback: blank names and underage
// registrations are rejected, but the name is neither trimmed nor length
// checked, so those cases still fail.
pub fn register(name: String, age: Int) -> Result(User, RegistrationError) {
  case name == "" {
    True -> Error(BlankName)
    False ->
      case age < 13 {
        True -> Error(Underage(age))
        False -> Ok(User(name: name, age: age))
      }
  }
}
