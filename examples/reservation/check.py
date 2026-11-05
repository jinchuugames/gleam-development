#!/usr/bin/env python3
"""Check both implementations against an isolated PostgreSQL container."""

import concurrent.futures
import json
import os
from pathlib import Path
import signal
import socket
import subprocess
import tempfile
import time
import urllib.error
import urllib.request
import uuid

ROOT = Path(__file__).resolve().parent
TOKEN = "local-example-token"


def run(*args, **kwargs):
    return subprocess.run(args, check=True, text=True, **kwargs)


def free_port():
    with socket.socket() as listener:
        listener.bind(("127.0.0.1", 0))
        return listener.getsockname()[1]


def wait_until(check, label, timeout=15):
    limit = time.monotonic() + timeout
    while time.monotonic() < limit:
        try:
            if check():
                return
        except (OSError, urllib.error.URLError):
            pass
        time.sleep(0.05)
    raise AssertionError(f"Timed out: {label}")


def request(port, path, body=None, token=TOKEN):
    data = None if body is None else json.dumps(body).encode()
    req = urllib.request.Request(
        f"http://127.0.0.1:{port}{path}", data=data,
        headers={"Authorization": f"Bearer {token}", "Content-Type": "application/json"},
    )
    try:
        response = urllib.request.urlopen(req, timeout=5)
    except urllib.error.HTTPError as error:
        response = error
    with response:
        content = response.read().decode()
        return response.status, json.loads(content) if path.startswith("/api/") else content


def stop(process):
    if process.poll() is None:
        os.killpg(process.pid, signal.SIGTERM)
        try:
            process.wait(timeout=10)
        except subprocess.TimeoutExpired:
            os.killpg(process.pid, signal.SIGKILL)
            process.wait()
            raise AssertionError("The server did not stop within ten seconds")


def exercise(language, command, cwd, env, sql):
    port = int(env["PORT"])
    log = tempfile.TemporaryFile(mode="w+")

    def start():
        process = subprocess.Popen(command, cwd=cwd, env=env, stdout=log, stderr=log, start_new_session=True)
        try:
            wait_until(lambda: process.poll() is None and request(port, "/")[0] == 200, "HTTP startup")
        except BaseException:
            stop(process)
            raise
        return process

    process = None
    try:
        process = start()
        assert "Stock reservation" in request(port, "/")[1]
        assert request(port, "/api/reservations", {}, token="wrong")[0] == 401
        assert request(port, "/api/reservations", {"key": "a", "sku": "keyboard", "quantity": 0})[0] == 400
        assert request(port, "/api/reservations", {"key": "a", "sku": "missing", "quantity": 1})[0] == 404
        assert request(port, "/api/reservations/missing")[0] == 404

        value = {"key": "retry", "sku": "keyboard", "quantity": 2}
        first = request(port, "/api/reservations", value)
        assert first[0] == 200, first
        assert request(port, "/api/reservations", value) == first
        assert sql("SELECT available FROM product WHERE sku='keyboard'") == "8"
        assert request(port, "/api/reservations", {**value, "quantity": 3}) == (409, {"error": "key_conflict"})

        def reserve(input):
            return request(port, "/api/reservations", input)

        sql("INSERT INTO product VALUES ('race',5), ('duplicate',10)")
        with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
            outcomes = list(pool.map(reserve, [
                {"key": f"race-{n}", "sku": "race", "quantity": 1} for n in range(12)
            ]))
            assert sum(code == 200 for code, _ in outcomes) == 5, outcomes
            assert sum(code == 409 for code, _ in outcomes) == 7, outcomes
            duplicates = list(pool.map(reserve, [
                {"key": "duplicate", "sku": "duplicate", "quantity": 2} for _ in range(8)
            ]))
            assert all(outcome == duplicates[0] for outcome in duplicates), duplicates
            assert duplicates[0][0] == 200, duplicates
        assert sql("SELECT available FROM product WHERE sku='race'") == "0"
        assert sql("SELECT available FROM product WHERE sku='duplicate'") == "8"

        # A lock holds the first write. Both servers must return a bounded failure.
        locker = subprocess.Popen(sql.command, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        locker.stdin.write("BEGIN; SELECT * FROM product WHERE sku='keyboard' FOR UPDATE; SELECT pg_sleep(3); COMMIT;\n")
        locker.stdin.close()
        wait_until(lambda: sql("SELECT count(*) FROM pg_stat_activity WHERE query LIKE '%pg_sleep(3)%' AND wait_event='PgSleep'") == "1", "database lock")
        before = time.monotonic()
        locked = reserve({"key": "timeout", "sku": "keyboard", "quantity": 1})
        assert locked[0] == 503, locked
        assert time.monotonic() - before < 4
        assert locker.wait(timeout=5) == 0
        assert sql("SELECT available FROM product WHERE sku='keyboard'") == "8"

        # Fail after the stock update, so the check proves transaction rollback.
        sql("""CREATE FUNCTION reject_test_insert() RETURNS trigger LANGUAGE plpgsql AS $$
          BEGIN
            IF NEW.request_key = 'rollback' THEN RAISE EXCEPTION 'forced insert failure'; END IF;
            RETURN NEW;
          END $$;
          CREATE TRIGGER reject_test_insert BEFORE INSERT ON reservation
          FOR EACH ROW EXECUTE FUNCTION reject_test_insert();""")
        assert reserve({"key": "rollback", "sku": "keyboard", "quantity": 1})[0] == 503
        assert sql("SELECT available FROM product WHERE sku='keyboard'") == "8"
        assert sql("SELECT count(*) FROM reservation WHERE request_key='rollback'") == "0"
        sql("DROP TRIGGER reject_test_insert ON reservation; DROP FUNCTION reject_test_insert()")

        # Force expiry in SQL so the check does not need a sixty-second sleep.
        sql("UPDATE reservation SET expires_at=0 WHERE request_key='retry'")
        wait_until(lambda: request(port, "/api/reservations/retry")[1]["status"] == "expired", "expiry")
        assert sql("SELECT available FROM product WHERE sku='keyboard'") == "10"
        replay = reserve(value)
        assert replay[0] == 200 and replay[1]["status"] == "expired", replay
        assert sql("SELECT available FROM product WHERE sku='keyboard'") == "10"

        # Stop with live reservations. A new process must recover from PostgreSQL.
        stop(process)
        sql("UPDATE reservation SET expires_at=0 WHERE status='held'")
        process = start()
        wait_until(lambda: sql("SELECT count(*) FROM reservation WHERE status='held'") == "0", "restart expiry")
        assert sql("SELECT available FROM product WHERE sku='race'") == "5"
        assert sql("SELECT available FROM product WHERE sku='duplicate'") == "10"
        # Several later sweeps must not credit the same rows again.
        time.sleep(0.6)
        assert sql("SELECT sum(available) FROM product") == "25"
        print(f"{language}: HTTP, validation, auth, retries, concurrency, timeout, rollback, expiry, restart, and shutdown passed", flush=True)
    except BaseException:
        log.seek(0)
        print(log.read())
        raise
    finally:
        if process is not None:
            stop(process)
        log.close()


def main():
    container = "gleam-reservation-" + uuid.uuid4().hex[:12]
    with tempfile.TemporaryDirectory(prefix="reservation-example-") as scratch:
        try:
            run("docker", "run", "--detach", "--rm", "--name", container,
                "-e", "POSTGRES_PASSWORD=example", "-p", "127.0.0.1::5432", "postgres:17-alpine", stdout=subprocess.DEVNULL)
            wait_until(lambda: subprocess.run(["docker", "exec", container, "pg_isready", "-h", "127.0.0.1", "-U", "postgres"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode == 0, "PostgreSQL startup", timeout=30)
            address = subprocess.check_output(["docker", "port", container, "5432/tcp"], text=True).strip()
            database_port = address.rsplit(":", 1)[1]
            for language in ("go", "gleam"):
                database = language + "_example"
                base = ["docker", "exec", "-i", container, "psql", "-U", "postgres", "-v", "ON_ERROR_STOP=1", "-Atq"]
                run(*base, input=f"CREATE DATABASE {database};", stdout=subprocess.DEVNULL)

                def sql(query):
                    return subprocess.check_output(sql.command, input=query, text=True).strip()

                sql.command = base + ["-d", database]
                run(*sql.command, input=(ROOT / "schema.sql").read_text(), stdout=subprocess.DEVNULL)
                env = {**os.environ, "DATABASE_URL": f"postgres://postgres:example@127.0.0.1:{database_port}/{database}?sslmode=disable",
                       "API_TOKEN": TOKEN, "PORT": str(free_port()), "SWEEP_MS": "100", "PAGE_PATH": str(ROOT / "web/index.html")}
                cwd = ROOT / language
                if language == "go":
                    run("go", "test", "-race", "./...", cwd=cwd, env=env)
                    binary = str(Path(scratch) / "reservation-go")
                    run("go", "build", "-o", binary, ".", cwd=cwd)
                    command = [binary]
                else:
                    run("gleam", "format", "--check", "src", "test", cwd=cwd)
                    run("gleam", "build", cwd=cwd)
                    run("gleam", "test", cwd=cwd, env=env)
                    run("gleam", "export", "erlang-shipment", cwd=cwd)
                    command = [str(cwd / "build/erlang-shipment/entrypoint.sh"), "run"]
                exercise(language, command, cwd, env, sql)
        finally:
            subprocess.run(["docker", "rm", "--force", container], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


if __name__ == "__main__":
    main()
