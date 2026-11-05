import gleam/erlang/process
import gleam/otp/actor
import gleam/otp/static_supervisor as supervisor
import gleam/otp/supervision
import gleeunit/should
import reservation_example/expiry

pub fn timer_survives_a_recoverable_error_test() {
  let observer = process.new_subject()
  let assert Ok(worker) =
    expiry.start(
      fn() {
        process.send(observer, "tick")
        Error(Nil)
      },
      10,
    )
  process.receive(observer, 1000) |> should.equal(Ok("tick"))
  process.receive(observer, 1000) |> should.equal(Ok("tick"))
  // Unlink before the deliberate kill so the test process survives.
  process.unlink(worker.pid)
  process.kill(worker.pid)
}

pub fn supervisor_restarts_the_worker_test() {
  let observer = process.new_subject()
  let assert Ok(tree) =
    supervisor.new(supervisor.OneForOne)
    |> supervisor.add(
      supervision.worker(fn() {
        let result = expiry.start(fn() { Ok(0) }, 1000)
        case result {
          Ok(actor.Started(pid, _)) -> process.send(observer, pid)
          Error(_) -> Nil
        }
        result
      }),
    )
    |> supervisor.start
  let assert Ok(first) = process.receive(observer, 1000)
  process.kill(first)
  let assert Ok(second) = process.receive(observer, 1000)
  { first != second } |> should.be_true
  process.unlink(tree.pid)
  process.kill(tree.pid)
}
