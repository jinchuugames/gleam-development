#!/usr/bin/env bash
# Verify the toolkit: formatting, examples, fixtures, lookup, benchmark guard.
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
skill="$root/skills/gleam-development"
api="$skill/scripts/gleam-api"
scratch=$(mktemp -d "${TMPDIR:-/tmp}/gleam-development-check.XXXXXX")
trap 'rm -rf -- "$scratch"' EXIT

step() { printf '\n== %s\n' "$1"; }

step "shell syntax"
bash -n "$api"
bash -n "$root/benchmarks/harness/run.sh"
bash -n "$root/benchmarks/harness/mock-agent.sh"
bash -n "$root/benchmarks/harness/regression-check.sh"
if command -v shellcheck >/dev/null; then
  shellcheck "$root/scripts/check.sh" "$api" "$root"/benchmarks/harness/*.sh
fi

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

step "fixture acceptance: the recorded correct attempt passes"
for taskdir in "$root"/benchmarks/tasks/*/; do
  task=$(basename "$taskdir")
  docs_variant="$taskdir/agent/docs"
  [ -d "$docs_variant" ] || continue
  work="$scratch/$task"
  cp -R "$taskdir/work" "$work"
  cp -R "$docs_variant"/. "$work"/
  cp "$taskdir/fixture-tests/$(jq -r '.fixture_module' "$taskdir/meta.json").gleam" "$work/test/"
  expected=$(( $(jq -r '.visible_tests' "$taskdir/meta.json") + $(jq -r '.fixture_tests' "$taskdir/meta.json") ))
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
[ -n "$multi" ] || {
  echo "LOOKUP FAILURE: multi-word search returned no records" >&2
  exit 1
}
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

step "installed skill includes the lookup script"
installed="$scratch/installed skill"
cp -R "$skill" "$installed"
[ -x "$installed/scripts/gleam-api" ] && [ ! -L "$installed/scripts/gleam-api" ] || {
  echo "INSTALL FAILURE: the skill has no bundled executable" >&2
  exit 1
}
installed_json=$(cd "$sample" && "$installed/scripts/gleam-api" sig gleam/dict.upsert --json)
printf '%s\n' "$installed_json" |
  jq -e '.[0] | .package == "gleam_stdlib" and .version == "1.0.5" and (.signature | startswith("pub fn upsert"))' >/dev/null
assert_contains "$("$root/scripts/gleam-api" sig gleam/dict.upsert --dir "$sample")" \
  "pub fn upsert(" "the repository alias still works"
echo "  the copied skill reads real pinned sources without a PATH change"

step "reuse detection"
# Two modules holding the same helper, one line apart: the copy an agent writes
# instead of reusing the original. `dupes` reads text, so the probe project does
# not need to compile.
dupe_probe="$scratch/dupe probe"
mkdir -p "$dupe_probe/src"
printf 'name = "dupe_probe"\nversion = "1.0.0"\ntarget = "erlang"\n' > "$dupe_probe/gleam.toml"
cat > "$dupe_probe/src/report.gleam" <<'GLEAM'
import gleam/string

pub fn shorten(text: String, max: Int) -> String {
  let trimmed = string.trim(text)
  let size = string.length(trimmed)
  case size <= max {
    True -> trimmed
    False -> string.slice(trimmed, at_index: 0, length: max) <> "..."
  }
}
GLEAM
cat > "$dupe_probe/src/report_extra.gleam" <<'GLEAM'
import gleam/string

// Copied from report.shorten and tweaked by one character: the duplicate an
// agent writes when it does not look for the original first.
pub fn shorten_copy(text: String, max: Int) -> String {
  let trimmed = string.trim(text)
  let size = string.length(trimmed)
  case size <= max + 1 {
    True -> trimmed
    False -> string.slice(trimmed, at_index: 0, length: max) <> "..."
  }
}
GLEAM
dupes=$("$api" dupes --dir "$dupe_probe")
assert_contains "$dupes" "shorten_copy" "dupes reports a copied helper"
assert_contains "$dupes" "report.gleam:3 shorten" "dupes names the original with its line"
clean=$("$api" dupes --dir "$root/examples/inventory")
assert_contains "$clean" "no near-duplicate function bodies" "a clean project reports none"
printf '%s\n' "$clean" | grep -q '~' && {
  echo "REUSE FAILURE: a clean project produced duplicate pairs" >&2
  exit 1
}
"$api" dupes --json --dir "$dupe_probe" |
  jq -e '.[0] | .similarity > 0.6 and (.a.symbol | contains("shorten")) and (.b.symbol | contains("shorten"))' >/dev/null || {
  echo "REUSE FAILURE: dupes --json is not the documented shape" >&2
  exit 1
}
echo "  --json returns similarity and both symbols"

step "recorded attempt variants compile"
mkdir -p "$scratch/variants"
for taskdir in "$root"/benchmarks/tasks/*/; do
  task=$(basename "$taskdir")
  for variant in feedback repair; do
    [ -d "$taskdir/agent/$variant" ] || { echo "FIXTURE FAILURE: $task has no agent/$variant" >&2; exit 1; }
    work="$scratch/variants/$task-$variant"
    rm -rf "$work"
    cp -R "$taskdir/work" "$work"
    cp -R "$taskdir/agent/$variant"/. "$work"/
    ( cd "$work" && gleam build >/dev/null ) || {
      echo "FIXTURE FAILURE: $task/agent/$variant does not compile" >&2
      exit 1
    }
    echo "  $task/$variant builds"
  done
done

step "benchmark refusals"
if "$root/benchmarks/harness/run.sh" --tasks word-frequency --conditions A \
    --out "$root/benchmark-out" >/dev/null 2>&1; then
  echo "GUARD FAILURE: an in-repository --out was accepted" >&2
  exit 1
fi
[ ! -e "$root/benchmark-out" ] || { echo "GUARD FAILURE: --out created a repository directory" >&2; exit 1; }
echo "  in-repository --out is refused"

step "benchmark self-check"
"$root/benchmarks/harness/run.sh" --self-check --out "$scratch/bench-selfcheck"

step "benchmark fixture replay"
"$root/benchmarks/harness/run.sh" --out "$scratch/bench" | tail -12

echo
echo "check.sh: all steps passed"
