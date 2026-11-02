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
out=$("$root/scripts/gleam-api" sig gleam/dict.upsert --dir "$sample")
printf '%s\n' "$out" | grep -q 'gleam_stdlib 1.0.5' || {
  echo "lookup did not report the pinned stdlib version" >&2
  exit 1
}
printf '%s\n' "$out" | grep -q 'gleam/dict' || { echo "lookup did not name the module" >&2; exit 1; }
if "$root/scripts/gleam-api" find dict.update --dir "$sample" >/dev/null 2>&1; then
  echo "lookup wrongly claimed dict.update exists" >&2
  exit 1
fi
"$root/scripts/gleam-api" find dict.update --dir "$sample" 2>/dev/null || true
echo "  find/sig/type behave against the pinned sources"

step "benchmark self-check"
"$root/benchmarks/harness/run.sh" --self-check --out "$scratch/bench-selfcheck"

step "benchmark fixture replay"
"$root/benchmarks/harness/run.sh" --out "$scratch/bench" | tail -12

echo
echo "check.sh: all steps passed"
