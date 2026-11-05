import gleam/erlang/process
import gleam/io
import gleam/otp/actor

pub type Message {
  Tick
}

type State {
  State(
    subject: process.Subject(Message),
    sweep: fn() -> Result(Int, Nil),
    interval: Int,
  )
}

// snippet:worker
pub fn start(
  sweep: fn() -> Result(Int, Nil),
  interval: Int,
) -> actor.StartResult(process.Subject(Message)) {
  actor.new_with_initialiser(1000, fn(subject) {
    let _ = process.send_after(subject, interval, Tick)
    Ok(
      actor.initialised(State(subject, sweep, interval))
      |> actor.returning(subject),
    )
  })
  |> actor.on_message(fn(state, _message) {
    case state.sweep() {
      Ok(_) -> Nil
      Error(_) -> io.println("expiry: database operation failed")
    }
    let _ = process.send_after(state.subject, state.interval, Tick)
    actor.continue(state)
  })
  |> actor.start
}
// end:worker
