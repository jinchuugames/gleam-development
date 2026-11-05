import envoy
import gleam/dynamic.{type Dynamic}
import gleam/erlang/process
import gleam/int
import gleam/otp/actor
import gleam/otp/static_supervisor as supervisor
import gleam/otp/supervision
import gleam/result
import gleam/time/timestamp
import mist
import pog
import reservation_example/expiry
import reservation_example/reservation
import reservation_example/web
import simplifile
import wisp
import wisp/wisp_mist

pub fn now() -> Int {
  timestamp.to_unix_seconds_and_nanoseconds(timestamp.system_time()).0
}

// snippet:supervisor
pub fn start(
  _type: Dynamic,
  _arguments: Dynamic,
) -> Result(process.Pid, actor.StartError) {
  let assert Ok(url) = envoy.get("DATABASE_URL")
  let assert Ok(token) = envoy.get("API_TOKEN")
  let assert True = token != ""
  let port = env_int("PORT", 8081)
  let interval = env_int("SWEEP_MS", 1000)
  let assert True = interval > 0 && port > 0 && port < 65_536
  let page_path = envoy.get("PAGE_PATH") |> result.unwrap("../web/index.html")
  let assert Ok(page) = simplifile.read(page_path)
  let name = process.new_name("reservation_db")
  let assert Ok(config) = pog.url_config(name, url)
  let config =
    config
    |> pog.pool_size(5)
    |> pog.connection_parameter("statement_timeout", "1500")
  let db = pog.named_connection(name)
  let dependencies = web.Dependencies(db, now, token, page)
  let http_server =
    fn(req) { web.handle(req, dependencies) }
    |> wisp_mist.handler(wisp.random_string(64))
    |> mist.new
    |> mist.bind("127.0.0.1")
    |> mist.port(port)

  // snippet:tree
  supervisor.new(supervisor.OneForOne)
  |> supervisor.add(pog.supervised(config))
  |> supervisor.add(
    supervision.worker(fn() {
      expiry.start(
        fn() { reservation.expire(db, now()) |> result.replace_error(Nil) },
        interval,
      )
    }),
  )
  |> supervisor.add(mist.supervised(http_server))
  |> supervisor.start
  |> result.map(fn(started) { started.pid })
  // end:tree
}

// end:supervisor

pub fn stop(_state: Dynamic) -> Nil {
  Nil
}

fn env_int(name: String, default: Int) -> Int {
  case envoy.get(name) {
    Error(_) -> default
    Ok(value) -> {
      let assert Ok(value) = int.parse(value)
      value
    }
  }
}
