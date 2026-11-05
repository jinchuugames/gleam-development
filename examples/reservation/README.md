# Reservation service: Go and Gleam

Read the [comparison guide](../../docs/go-to-gleam.md) for paired source excerpts and the design decisions.

Both applications provide a PostgreSQL reservation API, a periodic expiry worker, and the same browser page.
The Gleam handlers use Wisp. Mist supplies the HTTP transport through Wisp's adapter.
The browser uses JavaScript; there is no Lustre application in this example.

## Requirements

- Go 1.23 or newer.
- Gleam 1.19.2 or newer and Erlang/OTP 29.
- Python 3.10 or newer.
- Docker for the isolated database check.
- `psql` for the manual commands below.

## Automated check

Run this command from the repository root:

```sh
python3 examples/reservation/check.py
```

The check creates its own PostgreSQL container with a free host port.
It uses separate databases for Go and Gleam.
It removes its container after success or failure.
It does not read or modify an existing database.

The check runs the unit tests, the Go race detector, and the HTTP and database cases in the guide.
The Gleam tests require the database environment because the OTP application starts before the test entry point.
The check supplies that environment.

## Manual browser check

Start a separate example database from the repository root:

```sh
docker run --detach --rm --name reservation-guide-db \
  -e POSTGRES_PASSWORD=example -e POSTGRES_DB=reservation \
  -p 127.0.0.1:55439:5432 postgres:17-alpine
```

Wait until PostgreSQL accepts TCP connections:

```sh
docker exec reservation-guide-db pg_isready -h 127.0.0.1 -U postgres
```

Set the environment in the same terminal:

```sh
export DATABASE_URL='postgres://postgres:example@127.0.0.1:55439/reservation?sslmode=disable'
export API_TOKEN='local-example-token'
```

Apply the schema once to this empty database:

```sh
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f examples/reservation/schema.sql
```

Choose one server.

For Go:

```sh
cd examples/reservation/go
go run .
```

Open `http://127.0.0.1:8080`.

For Gleam, use a terminal with the same environment:

```sh
cd examples/reservation/gleam
gleam run
```

Open `http://127.0.0.1:8081`.
Enter `local-example-token` in the page.
Reserve two keyboards.
Repeat the request with the repeat button.
Wait sixty seconds for the reservation to expire.

Both servers can use this database concurrently. They share its stock and reservations.
The automated comparison instead gives each implementation its own database and initial stock.

Stop a manual server with its terminal interrupt command.
For Go, `go run` is a development wrapper; use a built executable to test signal behavior.
For Gleam, use an Erlang shipment to test the deployed entry point. The automated check uses both deployed entry points.

Stop the example database after the check.
This command removes the example container and its temporary database:

```sh
docker stop reservation-guide-db
```

## Configuration

| Variable | Default | Purpose |
| --- | --- | --- |
| `DATABASE_URL` | Required | PostgreSQL connection |
| `API_TOKEN` | Required and nonempty | Local example credential |
| `PORT` | Go: `8080`; Gleam: `8081` | Loopback HTTP port |
| `SWEEP_MS` | `1000` | Periodic expiry interval in milliseconds |
| `PAGE_PATH` | `../web/index.html` | Browser page, relative to the implementation directory |

The reservation lifetime is sixty seconds.
Both applications use a database pool with five connections and a 1500-millisecond PostgreSQL statement timeout.
The guide explains the additional client timeout and cancellation differences.

The token identifies one demonstration owner. The example does not implement account authentication or authorization for multiple owners.
