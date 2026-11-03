#!/usr/bin/env bash
# Exercise the harness with real downloaded dependencies and disposable agents.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../.." && pwd)
run="$here/run.sh"
scratch=$(mktemp -d "${TMPDIR:-/tmp}/gleam-bench-regression.XXXXXX")
trap 'rm -rf -- "$scratch"' EXIT
checks=0
check() {
  "$@" || { echo "REGRESSION FAILURE: $*" >&2; exit 1; }
  checks=$((checks + 1))
}
refuse() {
  local status=0
  "$run" --tasks word-frequency --conditions A --out "$scratch/refused" "$@" > "$scratch/refused.log" 2>&1 || status=$?
  check test "$status" -eq 2
  check test ! -e "$scratch/refused"
}

for value in E '' foo/bar .. ../escape 'A,' ',A' 'A,,B' 'A B' $'A\nB'; do refuse --conditions "$value"; done
for value in unknown '' word-frequency/../word-frequency .. word-frequency,unknown $'word-frequency\nunknown'; do refuse --tasks "$value"; done
for value in 0 -1 nope ''; do refuse --max-attempts "$value"; done
refuse --agent "$scratch/missing"
printf '#!/usr/bin/env bash\nexit 0\n' > "$scratch/nonexec"
refuse --agent "$scratch/nonexec"
refuse --out "$root/benchmark-out"
check test ! -e "$root/benchmark-out"
refuse --out "$scratch/../$(basename "$scratch")/new/../../$(basename "$scratch")/refused" --conditions ../escape
status=0
"$run" --agent > "$scratch/missing-value.log" 2>&1 || status=$?
check test "$status" -eq 2

# Neither path traversal nor a symlink may touch a sibling sentinel.
mkdir -p "$scratch/escape/word-frequency" "$scratch/links"
printf 'keep\n' > "$scratch/escape/word-frequency/sentinel"
refuse --conditions ../escape --out "$scratch/out"
for link in A .stage results.jsonl results.json; do
  ln -s "$scratch/escape" "$scratch/links/$link"
  refuse --out "$scratch/links"
  check test -L "$scratch/links/$link"
  unlink "$scratch/links/$link"
done
check grep -qx keep "$scratch/escape/word-frequency/sentinel"
# Validate the entire selection before truncating an existing result file.
mkdir -p "$scratch/existing"
printf 'keep\n' > "$scratch/existing/results.jsonl"
refuse --out "$scratch/existing" --tasks word-frequency,unknown
check grep -qx keep "$scratch/existing/results.jsonl"

agent="$scratch/agent with spaces.sh"
cat > "$agent" <<'AGENT'
#!/usr/bin/env bash
set -euo pipefail
[ -s "$BENCH_PROMPT_FILE" ]
[ -f "$BENCH_FEEDBACK_FILE" ]
case "$BENCH_CONDITION" in
  A|B) [ -z "${BENCH_DOCS_CMD+set}" ]; [ -z "${BENCH_SKILL_FILE+set}" ] ;;
  C) [ -x "$BENCH_DOCS_CMD" ]; [ -z "${BENCH_SKILL_FILE+set}" ] ;;
  D) [ -x "$BENCH_DOCS_CMD" ]; [ -s "$BENCH_SKILL_FILE" ] ;;
esac
printf 'yes\n' > "$BENCH_METRICS.ran"
case "${METRIC_CASE:-numeric}" in
  numeric) printf '{"files_read":2,"tokens":123}' > "$BENCH_METRICS" ;;
  zero) printf '{"tokens":0}' > "$BENCH_METRICS" ;;
  missing) printf '{}' > "$BENCH_METRICS" ;;
  empty) : > "$BENCH_METRICS" ;;
  absent) rm -f "$BENCH_METRICS" ;;
  malformed) printf '{' > "$BENCH_METRICS" ;;
  *) printf '{"tokens":%s}' "$METRIC_CASE" > "$BENCH_METRICS" ;;
esac
AGENT
chmod +x "$agent"
# The relative agent and output paths resolve before the harness changes cwd.
(cd "$scratch" && BENCH_DOCS_CMD=bad BENCH_SKILL_FILE=bad "$run" \
  --agent './agent with spaces.sh' --out 'relative output' --tasks word-frequency \
  --conditions A,B,C,D --max-attempts 1) > "$scratch/relative.log" 2>&1
check jq -e '.results | length == 4 and all(.[]; .tokens == 123 and .files_read == 2)' "$scratch/relative output/results.json"
for condition in A B C D; do
  check test -f "$scratch/relative output/$condition/word-frequency/agent-metrics.json.ran"
done
check test ! -d "$scratch/relative output/.stage/A-word-frequency"
check test ! -d "$scratch/relative output/.stage/B-word-frequency"
check test ! -e "$scratch/relative output/.stage/C-word-frequency/skill"

# Supported counts stay numeric; every unsupported value and absent file is null.
for value in zero missing empty absent malformed null '""' '"123"' '"bad"' true '[]' '{}' -1 1.5 9007199254740992; do
  METRIC_CASE="$value" "$run" --agent "$agent" --out "$scratch/metrics" \
    --tasks word-frequency --conditions A > "$scratch/metrics.log" 2>&1
  expected=null; [ "$value" != zero ] || expected=0
  # shellcheck disable=SC2016 # jq expands its own variables.
  check jq -e --argjson expected "$expected" '.results | length == 1 and .[0].tokens == $expected and (.[0] | has("tokens"))' "$scratch/metrics/results.json"
done

cat > "$scratch/retry-agent" <<'AGENT'
#!/usr/bin/env bash
set -euo pipefail
if [ "$BENCH_ATTEMPT" = 1 ]; then
  cp "$FIXTURE_ROOT/word-frequency/agent/feedback/src/word_frequency.gleam" src/word_frequency.gleam
  printf '{"tokens":17}' > "$BENCH_METRICS"
else
  [ -z "$(find . -iname '*zz_fixture_test*' -print)" ]
  [ ! -e ../fixture.log ]
  ! grep -q 'ties_sort_alphabetically_test' "$BENCH_FEEDBACK_FILE"
  printf 'yes\n' > "$BENCH_METRICS.isolated"
fi
AGENT
chmod +x "$scratch/retry-agent"
FIXTURE_ROOT="$root/benchmarks/tasks" "$run" --agent "$scratch/retry-agent" \
  --tasks word-frequency --conditions B --max-attempts 2 --out "$scratch/retry" > "$scratch/retry.log" 2>&1
check test -f "$scratch/retry/B/word-frequency/agent-metrics.json.isolated"
check jq -e '.results[0] | .attempts == 2 and .tokens == null' "$scratch/retry/results.json"

cat > "$scratch/discovery-agent" <<'AGENT'
#!/usr/bin/env bash
set -euo pipefail
cp "$FIXTURE_ROOT/target-split/agent/docs/src/greeting.gleam" src/greeting.gleam
sed '/^pub fn main()/i\
@target(erlang)\
' test/target_split_test.gleam > test/entry.tmp
mv test/entry.tmp test/target_split_test.gleam
printf '\n@target(javascript)\npub fn main() { Nil }\n' >> test/target_split_test.gleam
AGENT
chmod +x "$scratch/discovery-agent"
FIXTURE_ROOT="$root/benchmarks/tasks" "$run" --agent "$scratch/discovery-agent" \
  --tasks target-split --conditions C --max-attempts 1 --out "$scratch/discovery" > "$scratch/discovery.log" 2>&1
check grep -q 'DISCOVERY FAILURE (target-split/C/javascript)' "$scratch/discovery.log"
check jq -e '.results[0] | .final_pass == false and .first_attempt_pass == false' "$scratch/discovery/results.json"

cat > "$scratch/slow-agent" <<'AGENT'
#!/usr/bin/env bash
set -euo pipefail
cp "$FIXTURE_ROOT/word-frequency/agent/docs/src/word_frequency.gleam" src/word_frequency.gleam
sleep 3
AGENT
chmod +x "$scratch/slow-agent"
if command -v timeout >/dev/null || command -v gtimeout >/dev/null; then
  FIXTURE_ROOT="$root/benchmarks/tasks" BENCH_AGENT_TIMEOUT=1 "$run" --agent "$scratch/slow-agent" \
    --tasks word-frequency --conditions A --out "$scratch/timeout" > "$scratch/timeout.log" 2>&1
  check grep -q 'timed out' "$scratch/timeout/A/word-frequency/last.log"
  check jq -e '.results[0] | .final_pass == false and .first_attempt_pass == false' "$scratch/timeout/results.json"
fi

echo "regression-check: $checks assertions passed"
