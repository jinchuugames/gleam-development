pub type RegistrationError {
  BlankName
  NameTooShort(Int)
  Underage(Int)
}

pub type User {
  User(name: String, age: Int)
}

pub fn register(name: String, age: Int) -> Result(User, RegistrationError) {
  Ok(User(name: name, age: age))
}
