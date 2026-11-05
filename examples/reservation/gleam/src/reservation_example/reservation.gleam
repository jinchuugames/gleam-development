import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/result
import gleam/string
import pog

pub type Input {
  Input(key: String, sku: String, quantity: Int)
}

pub type Reservation {
  Reservation(
    key: String,
    sku: String,
    quantity: Int,
    status: Status,
    expires_at: Int,
  )
}

pub type Status {
  Held
  Expired
}

pub type Error {
  InvalidInput
  UnknownProduct
  UnknownReservation
  InsufficientStock
  KeyConflict
  Database(pog.QueryError)
}

pub fn input_decoder() -> decode.Decoder(Input) {
  use key <- decode.field("key", decode.string)
  use sku <- decode.field("sku", decode.string)
  use quantity <- decode.field("quantity", decode.int)
  decode.success(Input(key:, sku:, quantity:))
}

pub fn validate(input: Input) -> Result(Input, Error) {
  case
    valid_identifier(input.key)
    && valid_identifier(input.sku)
    && input.quantity >= 1
    && input.quantity <= 100
  {
    True -> Ok(input)
    False -> Error(InvalidInput)
  }
}

pub fn valid_identifier(value: String) -> Bool {
  string.length(value) >= 1
  && string.length(value) <= 64
  && list.all(string.to_utf_codepoints(value), fn(character) {
    let code = string.utf_codepoint_to_int(character)
    code == 45
    || code == 95
    || { code >= 97 && code <= 122 }
    || { code >= 65 && code <= 90 }
    || { code >= 48 && code <= 57 }
  })
}

fn row_decoder() -> decode.Decoder(Reservation) {
  use key <- decode.field(0, decode.string)
  use sku <- decode.field(1, decode.string)
  use quantity <- decode.field(2, decode.int)
  use status <- decode.field(
    3,
    decode.string
      |> decode.then(fn(status) {
        case status {
          "held" -> decode.success(Held)
          "expired" -> decode.success(Expired)
          _ -> decode.failure(Held, expected: "held or expired")
        }
      }),
  )
  use expires_at <- decode.field(4, decode.int)
  decode.success(Reservation(key:, sku:, quantity:, status:, expires_at:))
}

// snippet:create
pub fn create(
  db: pog.Connection,
  owner: String,
  input: Input,
  now: Int,
) -> Result(Reservation, Error) {
  use input <- result.try(validate(input))
  case pog.transaction(db, fn(tx) { reserve(tx, owner, input, now) }) {
    Ok(reservation) -> Ok(reservation)
    Error(pog.TransactionRolledBack(error)) -> Error(error)
    Error(pog.TransactionQueryError(error)) -> Error(Database(error))
  }
}

// end:create

// snippet:reserve
fn reserve(
  tx: pog.Connection,
  owner: String,
  input: Input,
  now: Int,
) -> Result(Reservation, Error) {
  use stock <- result.try(
    pog.query("SELECT available FROM product WHERE sku = $1 FOR UPDATE")
    |> pog.parameter(pog.text(input.sku))
    |> pog.returning(decode.field(0, decode.int, decode.success))
    |> execute(tx),
  )
  use available <- result.try(case stock.rows {
    [available] -> Ok(available)
    _ -> Error(UnknownProduct)
  })
  case find(tx, owner, input.key) {
    Ok(previous) ->
      case previous.sku == input.sku && previous.quantity == input.quantity {
        True -> Ok(previous)
        False -> Error(KeyConflict)
      }
    Error(UnknownReservation) ->
      case available >= input.quantity {
        False -> Error(InsufficientStock)
        True -> insert(tx, owner, input, now)
      }
    Error(error) -> Error(error)
  }
}

// end:reserve

fn insert(
  tx: pog.Connection,
  owner: String,
  input: Input,
  now: Int,
) -> Result(Reservation, Error) {
  use _ <- result.try(
    pog.query("UPDATE product SET available = available - $1 WHERE sku = $2")
    |> pog.parameter(pog.int(input.quantity))
    |> pog.parameter(pog.text(input.sku))
    |> execute(tx),
  )
  let reservation =
    Reservation(input.key, input.sku, input.quantity, Held, now + 60)
  case
    pog.query(
      "INSERT INTO reservation(owner_id, request_key, sku, quantity, status, expires_at) VALUES ($1, $2, $3, $4, 'held', $5)",
    )
    |> pog.parameter(pog.text(owner))
    |> pog.parameter(pog.text(input.key))
    |> pog.parameter(pog.text(input.sku))
    |> pog.parameter(pog.int(input.quantity))
    |> pog.parameter(pog.int(reservation.expires_at))
    |> execute(tx)
  {
    Ok(_) -> Ok(reservation)
    Error(Database(pog.ConstraintViolated(_, "reservation_pkey", _))) ->
      Error(KeyConflict)
    Error(error) -> Error(error)
  }
}

pub fn find(
  db: pog.Connection,
  owner: String,
  key: String,
) -> Result(Reservation, Error) {
  use rows <- result.try(
    pog.query(
      "SELECT request_key, sku, quantity, status, expires_at FROM reservation WHERE owner_id = $1 AND request_key = $2",
    )
    |> pog.parameter(pog.text(owner))
    |> pog.parameter(pog.text(key))
    |> pog.returning(row_decoder())
    |> execute(db),
  )
  case rows.rows {
    [reservation] -> Ok(reservation)
    _ -> Error(UnknownReservation)
  }
}

// snippet:expire
pub fn expire(db: pog.Connection, now: Int) -> Result(Int, Error) {
  use rows <- result.try(
    pog.query(
      "WITH expired AS (
      UPDATE reservation SET status = 'expired'
      WHERE status = 'held' AND expires_at <= $1
      RETURNING sku, quantity
    ), totals AS (
      SELECT sku, sum(quantity)::integer AS quantity FROM expired GROUP BY sku
    )
    UPDATE product SET available = available + totals.quantity
    FROM totals WHERE product.sku = totals.sku",
    )
    |> pog.parameter(pog.int(now))
    |> execute(db),
  )
  Ok(rows.count)
}

// end:expire

// snippet:execute
fn execute(
  query: pog.Query(row),
  db: pog.Connection,
) -> Result(pog.Returned(row), Error) {
  query
  |> pog.timeout(2000)
  |> pog.execute(db)
  |> result.map_error(Database)
}

// end:execute

pub fn to_json(reservation: Reservation) -> json.Json {
  json.object([
    #("key", json.string(reservation.key)),
    #("sku", json.string(reservation.sku)),
    #("quantity", json.int(reservation.quantity)),
    #(
      "status",
      json.string(case reservation.status {
        Held -> "held"
        Expired -> "expired"
      }),
    ),
    #("expires_at", json.int(reservation.expires_at)),
  ])
}
