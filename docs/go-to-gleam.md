# Go to Gleam: a reservation service

This guide compares the design of the same service in Go and Gleam.

1. Read the Go code example.
2. Compare it with the Gleam code example.

The examples use the same PostgreSQL schema, HTTP contract, and browser page.
The Gleam application uses **Wisp** for HTTP handlers. Mist supplies the HTTP transport through Wisp's adapter.

The source is in [`examples/reservation`](../examples/reservation/README.md).
Each code example comes from an executable file. The repository check rejects code examples that differ from their source files.

## The behavior

A customer reserves stock for sixty seconds. The API stores the reservation and removes the reserved quantity from available stock.
A periodic worker releases expired reservations. The browser shows the current status.

The service must obey these rules:

- Available stock never falls below zero.
- A repeated request with the same key reserves stock once.
- The same key with a different quantity or product returns a conflict.
- Expiry returns stock once.
- Reservations remain in the database after a server restart.
- The worker releases expired reservations after a server restart.

| Request | Result |
| --- | --- |
| `GET /` | The browser page |
| `POST /api/reservations` | A new reservation, or the current state of a reservation for a repeated request |
| `GET /api/reservations/:key` | The reservation for the authenticated owner |

The example checks one configured bearer token. That token identifies the owner `demo`.
The handler receives the owner identifier from this authentication check. The example does not provide a complete authentication system.

## 1. Files are API boundaries

The Go application has one package with four source files.
All files in that package can use its private functions.

```text
go/
  main.go          configuration, worker, application lifetime
  reservation.go   stock rules and database operations
  web.go           HTTP handlers
  reservation_test.go
```

The Gleam application has a module for each responsibility.
Each module declares the functions that other modules require as public.

```text
gleam/
  gleam.toml
  src/
    reservation_example.gleam
    reservation_example/
      application.gleam   configuration and the supervisor
      reservation.gleam   stock rules and database operations
      expiry.gleam        periodic work
      web.gleam           Wisp handlers
  test/
```

These directories contain one Go module and one Gleam package. Each application runs as one service.
The Gleam folder groups module names. A module cannot use private functions from another module in the folder.

Keep the reservation types, validation, SQL, and private helpers together.
A separate package for each operation adds dependency configuration. This example does not need those package boundaries.
Split a module when a separate responsibility needs its own API.
Use the responsibility to select the boundary.
Do not use file size alone to select the boundary.

This follows Gleam's guidance on [fragmented modules](https://gleam.run/documentation/conventions-patterns-and-anti-patterns/#Fragmented-modules).

## 2. Replace a receiver with explicit dependencies

The Go service contains a database pool and a clock. Its methods can use both.

<!-- source: examples/reservation/go/reservation.go#dependencies -->
```go
type Service struct {
	db  *pgxpool.Pool
	now func() time.Time
}

func NewService(db *pgxpool.Pool, now func() time.Time) *Service {
	return &Service{db: db, now: now}
}
```

The Wisp handler receives a dependency record. The reservation functions receive only the values they need.

<!-- source: examples/reservation/gleam/src/reservation_example/web.gleam#dependencies -->
```gleam
pub type Dependencies {
  Dependencies(
    db: pog.Connection,
    now: fn() -> Int,
    token: String,
    page: String,
  )
}
```

The database field is a pool handle. The clock is a function.
The record does not contain a copy of the database or a mutable service object.

Both applications receive dependencies explicitly. The Go receiver contains the dependencies. The Gleam functions receive them as arguments.
The Gleam application needs no method table or actor for these operations.

The Go read helper has a small interface because both `pgxpool.Pool` and `pgx.Tx` implement its operation.
Pog represents a pool and a transaction with the same `Connection` type, so the Gleam helper requires no equivalent interface.
Use the library types before you introduce a general store interface.

## 3. Follow one HTTP request

The Go handler sets an operation deadline. It decodes the input, calls the service, and converts the result into an HTTP response.

<!-- source: examples/reservation/go/web.go#handler -->
```go
func (h Handler) route(w http.ResponseWriter, r *http.Request, owner string) {
	ctx, cancel := context.WithTimeout(r.Context(), 2*time.Second)
	defer cancel()
	var reservation Reservation
	var err error
	switch {
	case r.Method == http.MethodPost && r.URL.Path == "/api/reservations":
		if strings.Split(r.Header.Get("Content-Type"), ";")[0] != "application/json" {
			writeJSON(w, 415, map[string]string{"error": "unsupported_media_type"})
			return
		}
		var input Input
		decoder := json.NewDecoder(http.MaxBytesReader(w, r.Body, 4096))
		if err = decoder.Decode(&input); err == nil {
			var extra any
			if decoder.Decode(&extra) != io.EOF {
				err = ErrInvalidInput
			}
		}
		if err != nil {
			writeJSON(w, 400, map[string]string{"error": "invalid_input"})
			return
		}
		reservation, err = h.service.Create(ctx, owner, input)
	case r.Method == http.MethodGet && strings.HasPrefix(r.URL.Path, "/api/reservations/"):
		reservation, err = find(ctx, h.service.db, owner, strings.TrimPrefix(r.URL.Path, "/api/reservations/"))
	default:
		err = ErrNotFound
	}
	respond(w, reservation, err)
}
```

The Wisp handler performs the same work. `require_json` checks the content type and reads the body.
The decoder checks the structure of the input. The reservation module checks the business rules.

<!-- source: examples/reservation/gleam/src/reservation_example/web.gleam#handler -->
```gleam
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
```

Both handlers receive `owner` from the authentication check. Neither accepts an owner identifier from the JSON body.
Both SQL reads include the owner identifier, so a request key alone does not select another owner's reservation.

`use` supplies a callback to Wisp. It does not create a goroutine, a transaction, or a cancellation scope.
The handler remains ordinary application code.

## 4. Transactions and error values

The Go application starts the transaction explicitly. A deferred rollback cancels the transaction if a failure prevents a successful commit.

<!-- source: examples/reservation/go/reservation.go#create -->
```go
func (s *Service) Create(ctx context.Context, owner string, input Input) (Reservation, error) {
	if err := validate(input); err != nil {
		return Reservation{}, err
	}
	tx, err := s.db.Begin(ctx)
	if err != nil {
		return Reservation{}, err
	}
	defer tx.Rollback(context.Background())
	reservation, err := reserve(ctx, tx, owner, input, s.now().Unix())
	if err != nil {
		return Reservation{}, err
	}
	if err := tx.Commit(ctx); err != nil {
		return Reservation{}, err
	}
	return reservation, nil
}
```

Pog controls the transaction through a callback. `Ok` permits a commit. `Error` causes a rollback.

<!-- source: examples/reservation/gleam/src/reservation_example/reservation.gleam#create -->
```gleam
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
```

Both applications distinguish an expected refusal from a database failure.
Gleam names those cases in a custom error type: `InsufficientStock`, `KeyConflict`, and `Database(error)`.
The Wisp handler converts those values into HTTP responses.

Recoverable failures return `Result`. A reservation function must not use `let assert` for stock availability or client input.
The application uses assertions for required configuration at startup. A configuration refusal stops the application.

## 5. Immutability does not protect shared database state

The Go transaction locks the product row before it checks stock.
It then checks whether the owner already used this request key.

<!-- source: examples/reservation/go/reservation.go#reserve -->
```go
func reserve(ctx context.Context, tx pgx.Tx, owner string, input Input, now int64) (Reservation, error) {
	var available int
	err := tx.QueryRow(ctx, "SELECT available FROM product WHERE sku = $1 FOR UPDATE", input.SKU).Scan(&available)
	if errors.Is(err, pgx.ErrNoRows) {
		return Reservation{}, ErrNotFound
	}
	if err != nil {
		return Reservation{}, err
	}
	previous, err := find(ctx, tx, owner, input.Key)
	if err == nil {
		if previous.SKU != input.SKU || previous.Quantity != input.Quantity {
			return Reservation{}, ErrKeyConflict
		}
		return previous, nil
	}
	if !errors.Is(err, ErrNotFound) {
		return Reservation{}, err
	}
	if available < input.Quantity {
		return Reservation{}, ErrStock
	}
	return insert(ctx, tx, owner, input, now)
}
```

The Gleam transaction uses the same lock and the same order.

<!-- source: examples/reservation/gleam/src/reservation_example/reservation.gleam#reserve -->
```gleam
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
```

Two HTTP requests can run concurrently in either application.
An immutable Gleam value does not serialize PostgreSQL updates.
The database lock protects stock across connections and across server instances.

A local actor serializes only the requests that it receives.
Another application instance can write to the same database without that actor. The transaction remains necessary.

The primary key is `(owner_id, request_key)`.
Concurrent requests for the same key cannot create two reservations.
A uniqueness failure also causes a rollback of the stock update in that transaction.

Request keys remain in the database after expiry. A retry returns the expired reservation. It does not create a new reservation.
A new reservation requires a new key.

## 6. Context has separate responsibilities

These responsibilities often appear together in Go code. Each requires a separate decision in Gleam.

| Responsibility | Go example | Gleam example |
| --- | --- | --- |
| Dependencies | `Service` fields | Explicit arguments and the Wisp dependency record |
| Caller identity | `owner` after authentication | The same explicit `owner` argument |
| Request cancellation | `r.Context()` passed into pgx | No equivalent request cancellation token in this example |
| Operation deadline | `context.WithTimeout` around the request | A timeout for each Pog query and PostgreSQL statement |
| Application lifetime | Signal context and explicit cleanup | An OTP application and its supervisor |
| Work that survives a restart | Reservation rows in PostgreSQL | The same rows in PostgreSQL |

The Go application passes the request context to pool acquisition, queries, and commit.
A client disconnect can cancel that context.

The Gleam query helper sets a client timeout:

<!-- source: examples/reservation/gleam/src/reservation_example/reservation.gleam#execute -->
```gleam
fn execute(
  query: pog.Query(row),
  db: pog.Connection,
) -> Result(pog.Returned(row), Error) {
  query
  |> pog.timeout(2000)
  |> pog.execute(db)
  |> result.map_error(Database)
}
```

Both pools also configure PostgreSQL `statement_timeout` to 1500 milliseconds.
This limit can stop a query after the application stops its wait for a response.

These mechanisms are not equivalent.
The Go deadline applies to the complete operation.
The Gleam timeout applies to each query separately. Pool acquisition has a separate timeout.
The Gleam example does not cancel a transaction when the browser disconnects.

A commit can succeed before the client receives its response. Cancellation cannot prove that no write occurred.
If the caller does not know the result, it can repeat the request with the same key in either application.

A dependency record named `Context` does not automatically provide cancellation.
Use separate values for dependencies, identity, deadlines, and process lifetime.

## 7. A ticker loop becomes a small supervised process

The Go worker creates a ticker and checks its lifetime context.
It executes one sweep at a time and reports recoverable failures.

<!-- source: examples/reservation/go/main.go#worker -->
```go
func runExpiry(ctx context.Context, interval time.Duration, sweep func(context.Context) error) {
	ticker := time.NewTicker(interval)
	defer ticker.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			operation, cancel := context.WithTimeout(ctx, 2*time.Second)
			if err := sweep(operation); err != nil {
				log.Printf("expiry: %v", err)
			}
			cancel()
		}
	}
}
```

The Gleam actor receives a typed timer message. Its state contains its callback, interval, and message subject.

<!-- source: examples/reservation/gleam/src/reservation_example/expiry.gleam#worker -->
```gleam
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
```

The process is necessary because periodic work continues independently of HTTP requests.
The reservation rules and SQL functions remain ordinary functions.

The schedules differ.
Go's ticker uses a regular interval. It can discard ticks when the receiver takes too long.
The Gleam worker schedules its next tick after the sweep completes. The delay prevents a queue of timer messages between sweeps.
Both workers release expired reservations on a later sweep. Each worker executes one sweep at a time.

A database refusal is an error value. The worker reports it and waits for the next tick.
A process crash is a different event. The Gleam supervisor can restart the worker.

## 8. Process restart and stored reservations

The application starts the database pool, the worker, and the Wisp HTTP transport under one supervisor.

<!-- source: examples/reservation/gleam/src/reservation_example/application.gleam#tree -->
```gleam
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
```

The callback retains a named pool handle. It can use the same handle after the pool process restarts.
`OneForOne` restarts the failed child. It does not restart all children for every failure.
The supervisor limits the number of restarts within a time interval. Repeated crashes can stop the supervisor.

PostgreSQL stores the reservations.
A new worker reads the database to find reservations that expired while the service was stopped.

Expiry changes status and returns stock in one SQL statement:

<!-- source: examples/reservation/go/reservation.go#expire -->
```go
func (s *Service) Expire(ctx context.Context) error {
	_, err := s.db.Exec(ctx, `WITH expired AS (
		UPDATE reservation SET status = 'expired'
		WHERE status = 'held' AND expires_at <= $1
		RETURNING sku, quantity
	), totals AS (
		SELECT sku, sum(quantity)::integer AS quantity FROM expired GROUP BY sku
	)
	UPDATE product SET available = available + totals.quantity
	FROM totals WHERE product.sku = totals.sku`, s.now().Unix())
	return err
}
```

Only rows that change from `held` to `expired` return stock.
A later sweep cannot select those rows again because their status is `expired`.
PostgreSQL commits both changes or neither change.

The database preserves the work after a restart. A supervisor alone cannot restore a lost reservation or prevent a duplicate stock credit.

## 9. Define the shutdown behavior

The Go application cancels the worker, permits HTTP requests to finish, waits for the worker, and then closes the pool.

<!-- source: examples/reservation/go/main.go#shutdown -->
```go
	select {
	case <-root.Done():
	case err = <-serverDone:
	}
	stop()
	drain, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	shutdownErr := server.Shutdown(drain)
	if shutdownErr != nil {
		server.Close()
	}
	<-workerDone
```

The Gleam package registers an OTP application callback in `gleam.toml`.
OTP controls the supervisor and its children.
During an orderly shutdown, the supervisor stops children in reverse startup order:

1. The HTTP transport.
2. The worker.
3. The database pool.

The applications do not provide the same behavior for active requests during shutdown.
Go calls `Server.Shutdown` with a limit of five seconds.
The Gleam example uses the transport's OTP shutdown behavior.
It does not provide an equivalent operation that waits for active HTTP requests to finish.

A stopped connection can leave the caller uncertain about a commit.
The transaction and request key remain necessary during shutdown and restart.
An uncatchable process kill can prevent cleanup in either application.

## 10. Use one browser to compare the server designs

Both servers serve the same small HTML page with JavaScript.
The browser submits JSON, shows an error or reservation, and polls its status.

<!-- source: examples/reservation/web/index.html#browser -->
```javascript
async function api(path, options = {}) {
  const response = await fetch(path, {
    ...options,
    headers: {
      'Authorization': `Bearer ${document.querySelector('#token').value}`,
      'Content-Type': 'application/json'
    }
  });
  const body = await response.json();
  if (!response.ok) throw new Error(body.error || `HTTP ${response.status}`);
  return body;
}
```

The repeat button sends the original request key and quantity.
A new reservation uses a new key.
The page displays response data with `textContent`, so API text does not become executable HTML.

Both applications use the same browser code. This guide compares Go and Gleam server idioms.
A comparison with Lustre requires separate examples of browser state and effects.
These examples show the server's dependency, transaction, and process boundaries.

## 11. Check the failure cases

Run the complete comparison from the repository root:

```sh
python3 examples/reservation/check.py
```

The check creates an isolated PostgreSQL container and one database per implementation.
It compiles both applications, runs their tests, starts each server, and sends real HTTP requests.
It also runs Go's race detector.

| Check | Required result |
| --- | --- |
| Incorrect bearer token | Reject the request before database access |
| Invalid quantity | Reject the request |
| The product does not exist | Return a refusal without a stock change |
| Repeated request | Return the same reservation without a second stock change |
| Same key, changed quantity | Return a conflict |
| Concurrent reservations | Accept only the quantity that stock permits |
| Concurrent identical requests | Create one reservation |
| A database lock exceeds the statement limit | Return a bounded failure without a stock change |
| An insert fails after the stock update | A rollback cancels the stock update. No reservation exists. |
| Expiry | Return stock once |
| Retry after expiry | Return the expired reservation |
| Server restart | The worker finds expired reservations and restores stock once. |
| Worker crash | The Gleam unit test observes a replacement worker |
| Termination signal | Stop the server within ten seconds |

The HTTP check fetches the browser page. It does not execute browser JavaScript.
Manual browser checks use the commands in the [example README](../examples/reservation/README.md).

The example has no checkout confirmation, reservation deletion, migration system, or token issuer.
Both listeners bind to loopback. PostgreSQL uses a local example password and disables TLS for this local exercise.
These limits apply only to this local example. They do not specify the configuration for a deployed service.

## Source and maintenance

The manifest and `go.sum` record the dependency versions. The application uses Pog 4.1.0 and Wisp 2.2.2.
The examples require the Erlang target. They do not claim browser compatibility for OTP or PostgreSQL code.

After a source change, do these steps from the repository root:

1. Update the code examples:

```sh
python3 scripts/sync-go-to-gleam.py
```

2. Check that the code examples match their source files:

```sh
python3 scripts/sync-go-to-gleam.py --check
```

Primary references:

- [Gleam conventions and module design](https://gleam.run/documentation/conventions-patterns-and-anti-patterns/)
- [Pog 4.1.0](https://hexdocs.pm/pog/4.1.0/pog.html)
- [Wisp 2.2.2](https://hexdocs.pm/wisp/2.2.2/wisp.html)
- [Gleam OTP 1.3.0 actors](https://hexdocs.pm/gleam_otp/1.3.0/gleam/otp/actor.html)
- [Go context](https://pkg.go.dev/context)
- [Go HTTP server shutdown](https://pkg.go.dev/net/http#Server.Shutdown)
- [PostgreSQL row locks](https://www.postgresql.org/docs/17/explicit-locking.html#LOCKING-ROWS)
