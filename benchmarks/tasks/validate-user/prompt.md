# Validate user registration

Implement `register` in `src/registration.gleam`:

```gleam
pub fn register(name: String, age: Int) -> Result(User, RegistrationError)
```

The types are already defined in the module:

```gleam
pub type RegistrationError {
  BlankName
  NameTooShort(Int)
  Underage(Int)
}

pub type User {
  User(name: String, age: Int)
}
```

The name must be trimmed of surrounding whitespace before it is checked or
stored. Rules, in this order:

- a name that is empty after trimming is rejected with `Error(BlankName)`;
- a trimmed name shorter than 3 characters is rejected with
  `Error(NameTooShort(length))` where `length` is the trimmed length;
- an age below 13 is rejected with `Error(Underage(age))`;
- otherwise the registration succeeds with `Ok(User(name: trimmed_name, age: age))`.

The visible tests in `test/` cover the basic case. Keep them passing, and do
not change their expectations.
