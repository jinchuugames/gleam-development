import gleam/erlang/process
import gleam/http
import gleam/json
import gleeunit/should
import pog
import reservation_example/web
import wisp/simulate

fn dependencies() -> web.Dependencies {
  web.Dependencies(
    pog.named_connection(process.new_name("unused_test_pool")),
    fn() { 100 },
    "secret",
    "<h1>Stock reservation</h1>",
  )
}

pub fn unauthorized_request_does_not_reach_the_database_test() {
  simulate.request(http.Post, "/api/reservations")
  |> web.handle(dependencies())
  |> fn(response) { response.status |> should.equal(401) }
}

pub fn invalid_json_shape_does_not_reach_the_database_test() {
  simulate.request(http.Post, "/api/reservations")
  |> simulate.header("authorization", "Bearer secret")
  |> simulate.json_body(json.object([#("quantity", json.int(1))]))
  |> web.handle(dependencies())
  |> fn(response) { response.status |> should.equal(400) }
}

pub fn page_does_not_need_a_database_test() {
  simulate.request(http.Get, "/")
  |> web.handle(dependencies())
  |> simulate.read_body
  |> should.equal("<h1>Stock reservation</h1>")
}
