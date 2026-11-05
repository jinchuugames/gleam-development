import gleam/dynamic/decode
import gleam/http
import gleam/http/request
import gleam/json
import pog
import reservation_example/reservation
import wisp

// snippet:dependencies
pub type Dependencies {
  Dependencies(
    db: pog.Connection,
    now: fn() -> Int,
    token: String,
    page: String,
  )
}

// end:dependencies

pub fn handle(req: wisp.Request, dependencies: Dependencies) -> wisp.Response {
  case req.method, wisp.path_segments(req) {
    http.Get, [] -> wisp.html_response(dependencies.page, 200)
    _, ["api", ..] ->
      case
        request.get_header(req, "authorization")
        == Ok("Bearer " <> dependencies.token)
      {
        False -> error_response(401, "unauthorized")
        True -> route(req, dependencies, "demo")
      }
    _, _ -> error_response(404, "not_found")
  }
}

// snippet:handler
fn route(
  req: wisp.Request,
  dependencies: Dependencies,
  owner: String,
) -> wisp.Response {
  case req.method, wisp.path_segments(req) {
    http.Post, ["api", "reservations"] -> {
      use body <- wisp.require_json(wisp.set_max_body_size(req, 4096))
      case decode.run(body, reservation.input_decoder()) {
        Error(_) -> error_response(400, "invalid_input")
        Ok(input) ->
          reservation.create(dependencies.db, owner, input, dependencies.now())
          |> respond
      }
    }
    http.Get, ["api", "reservations", key] ->
      reservation.find(dependencies.db, owner, key)
      |> respond
    _, _ -> error_response(404, "not_found")
  }
}

// end:handler

fn respond(
  result: Result(reservation.Reservation, reservation.Error),
) -> wisp.Response {
  case result {
    Ok(value) ->
      wisp.json_response(json.to_string(reservation.to_json(value)), 200)
    Error(reservation.InvalidInput) -> error_response(400, "invalid_input")
    Error(reservation.UnknownProduct) | Error(reservation.UnknownReservation) ->
      error_response(404, "not_found")
    Error(reservation.InsufficientStock) ->
      error_response(409, "insufficient_stock")
    Error(reservation.KeyConflict) -> error_response(409, "key_conflict")
    Error(reservation.Database(_)) ->
      error_response(503, "database_unavailable")
  }
}

fn error_response(status: Int, error: String) -> wisp.Response {
  wisp.json_response(
    json.to_string(json.object([#("error", json.string(error))])),
    status,
  )
}
