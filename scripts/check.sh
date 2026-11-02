#!/usr/bin/env bash
# Verify the toolkit: formatting, examples, fixtures, lookup, benchmark guard.
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
scratch="${TMPDIR:-/tmp}/gleam-development-check"
rm -rf "$scratch"
mkdir -p "$scratch"

step() { printf '\n== %s\n' "$1"; }

step "shell syntax"
bash -n "$root/scripts/gleam-api"
bash -n "$root/benchmarks/harness/run.sh"
bash -n "$root/benchmarks/harness/mock-agent.sh"

step "formatting"
for dir in "$root"/examples/*/ "$root"/benchmarks/tasks/*/work/; do
  [ -f "$dir/gleam.toml" ] || continue
  ( cd "$dir" && gleam format --check src test )
  echo "  formatted: ${dir#"$root"/}"
done

step "examples build and test"
for dir in "$root"/examples/*/; do
  [ -f "$dir/gleam.toml" ] || continue
  name=$(basename "$dir")
  echo "  $name"
  ( cd "$dir" && gleam build >/dev/null && gleam test >/dev/null )
  if grep -q 'target = "erlang"' "$dir/gleam.toml"; then
    ( cd "$dir" && gleam build --target javascript >/dev/null && gleam test --target javascript >/dev/null )
    echo "  $name (javascript) ok"
  fi
done

step "fixture acceptance: correct attempt passes hidden tests"
for taskdir in "$root"/benchmarks/tasks/*/; do
  task=$(basename "$taskdir")
  docs_variant="$taskdir/agent/docs"
  [ -d "$docs_variant" ] || continue
  work="$scratch/$task"
  cp -R "$taskdir/work" "$work"
  cp -R "$docs_variant"/. "$work"/
  cp "$taskdir/hidden/$(jq -r '.hidden_module' "$taskdir/meta.json").gleam" "$work/test/"
  expected=$(( $(jq -r '.visible_tests' "$taskdir/meta.json") + $(jq -r '.hidden_tests' "$taskdir/meta.json") ))
  for target in $(jq -r '.targets[]' "$taskdir/meta.json"); do
    out=$( cd "$work" && gleam test --target "$target" 2>&1 )
    passed=$(printf '%s\n' "$out" | grep -Eo '[0-9]+ passed' | tail -1 | grep -Eo '[0-9]+')
    if [ -z "$passed" ] || [ "$passed" -lt "$expected" ]; then
      printf '%s\n' "$out" | tail -20
      echo "FIXTURE FAILURE: $task ($target) ran ${passed:-0} tests, expected $expected" >&2
      exit 1
    fi
    echo "  $task ($target): $passed tests"
  done
done

step "documentation lookup against a pinned project"
sample="$scratch/word-frequency"
api="$root/scripts/gleam-api"

assert_contains() { # $1 haystack, $2 needle, $3 label
  printf '%s\n' "$1" | grep -F -q "$2" || {
    printf '%s\n' "$1" | head -5
    echo "LOOKUP FAILURE: $3 did not contain: $2" >&2
    exit 1
  }
  echo "  $3"
}

assert_contains "$("$api" packages --dir "$sample")" "gleam_stdlib 1.0.5" "packages reports the pinned version"
assert_contains "$("$api" sig gleam/dict.upsert --dir "$sample")" "pub fn upsert(" "sig returns the real signature"
assert_contains "$("$api" sig gleam/dict.upsert --dir "$sample")" "gleam_stdlib 1.0.5" "sig names the package and version"
assert_contains "$("$api" find upsert --dir "$sample")" "gleam/dict" "find returns the owning module"
assert_contains "$("$api" type Dict --dir "$sample")" "pub type Dict(key, value)" "type returns the custom type"
assert_contains "$("$api" module gleam/dict --dir "$sample")" "pub fn upsert(" "module lists public symbols"

single=$("$api" search upsert --dir "$sample")
multi=$("$api" search remove a key --dir "$sample")
quoted=$("$api" search "remove a key" --dir "$sample")
assert_contains "$single" "upsert" "single-word search finds the symbol"
[ "$multi" = "$quoted" ] || {
  echo "LOOKUP FAILURE: unquoted multi-word search differs from the quoted form" >&2
  exit 1
}
echo "  multi-word search ANDs every word"

json=$("$api" find upsert --json --dir "$sample")
printf '%s\n' "$json" | jq -e '.[0] | .package == "gleam_stdlib" and .version == "1.0.5" and (.signature | startswith("pub fn upsert"))' >/dev/null || {
  echo "LOOKUP FAILURE: --json output is not the documented shape" >&2
  printf '%s\n' "$json" | head -3
  exit 1
}
echo "  --json returns package, version, and signature"

if "$api" find dict.update --dir "$sample" >/dev/null 2>&1; then
  echo "LOOKUP FAILURE: find claimed dict.update exists" >&2
  exit 1
fi
echo "  absent symbol exits non-zero"

if "$api" sig gleam/list.upsert --dir "$sample" >/dev/null 2>&1; then
  echo "LOOKUP FAILURE: sig found upsert in the wrong module" >&2
  exit 1
fi
echo "  wrong-module lookup exits non-zero"

step "benchmark self-check"
"$root/benchmarks/harness/run.sh" --self-check --out "$scratch/bench-selfcheck"

step "benchmark fixture replay"
"$root/benchmarks/harness/run.sh" --out "$scratch/bench" | tail -12

echo
echo "check.sh: all steps passed"
