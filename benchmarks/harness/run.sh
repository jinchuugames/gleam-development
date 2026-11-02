#!/usr/bin/env bash
# Benchmark harness: evaluate an agent on hidden-test Gleam tasks under four
# conditions (A baseline, B compiler feedback, C +docs lookup, D +skill).
#
# The harness owns the task fixture, the compiler, and the hidden tests. The
# agent only ever sees its own work directory.
#
#   ./run.sh                                   # all tasks, all conditions, mock agent
#   ./run.sh --tasks cart-totals --conditions A,B
#   ./run.sh --agent ./my-agent.sh --json results.json
#   ./run.sh --self-check                      # prove the discovery guard fires
#
# Agent contract (see benchmarks/README.md):
#   executed with cwd = the task work directory, prompt in $BENCH_PROMPT_FILE
#   env: BENCH_TASK BENCH_CONDITION BENCH_ATTEMPT BENCH_VARIANT BENCH_FEEDBACK_FILE
#        BENCH_SKILL_FILE BENCH_DOCS_CMD BENCH_METRICS
set -uo pipefail

here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../.." && pwd)
tasks_dir="$root/benchmarks/tasks"
agent="$root/benchmarks/harness/mock-agent.sh"
out="${BENCH_OUT:-/tmp/gleam-bench}"
model="${BENCH_MODEL:-mock}"
conditions="A,B,C,D"
selected=""
json_out=""
max_attempts=3
self_check=false

while [ $# -gt 0 ]; do
  case "$1" in
    --agent) agent="$2"; shift 2 ;;
    --tasks) selected="$2"; shift 2 ;;
    --conditions) conditions="$2"; shift 2 ;;
    --max-attempts) max_attempts="$2"; shift 2 ;;
    --out) out="$2"; shift 2 ;;
    --json) json_out="$2"; shift 2 ;;
    --self-check) self_check=true; shift ;;
    -h|--help) sed -n '2,26p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "run.sh: unknown option $1" >&2; exit 2 ;;
  esac
done

command -v gleam >/dev/null || { echo "run.sh: gleam not on PATH" >&2; exit 2; }
command -v jq >/dev/null || { echo "run.sh: jq not on PATH" >&2; exit 2; }
[ -x "$agent" ] || { echo "run.sh: agent not executable: $agent" >&2; exit 2; }

compiler_version=$(gleam --version 2>/dev/null | head -1)
stdlib_version=$(sed -n 's/^ *{ name = "gleam_stdlib", version = "\([^"]*\)".*/\1/p' \
  "$tasks_dir"/*/work/manifest.toml 2>/dev/null | sort -u | paste -sd, -)

mkdir -p "$out"
start_time=$(date +%s)
results_file="$out/results.jsonl"
: > "$results_file"

pick_variant() { # $1 condition, $2 attempt
  local condition="$1" attempt="$2" tdir="$3"
  if [ "$condition" = "A" ]; then echo baseline; return; fi
  if [ "$attempt" -gt 1 ]; then
    [ -d "$tdir/agent/feedback" ] && { echo feedback; return; }
  fi
  case "$condition" in
    B) echo baseline ;;
    *) [ -d "$tdir/agent/docs" ] && echo docs || echo baseline ;;
  esac
}

# Highest number of executed tests across the target summaries in a log.
# Counts passed + failures + skipped, so a failing test still proves execution.
executed_tests() {
  awk '
    /[0-9]+ passed/ {
      p = 0; f = 0; s = 0
      if (match($0, /[0-9]+ passed/)) p = substr($0, RSTART, RLENGTH) + 0
      if (match($0, /[0-9]+ failures?/)) f = substr($0, RSTART, RLENGTH) + 0
      if (match($0, /[0-9]+ skipped/)) s = substr($0, RSTART, RLENGTH) + 0
      if (p + f + s > max) max = p + f + s
    }
    END { print max + 0 }
  ' "$1"
}

# Refuse a run whose hidden tests did not actually execute.
verify_discovery() { # $1 work dir, $2 meta, $3 test output, $4 label
  local work="$1" meta="$2" log="$3" label="$4"
  local hidden_module entry expected passed
  hidden_module=$(jq -r '.hidden_module' "$meta")
  entry=$(jq -r '.entry_module // empty' "$meta")
  if [ -z "$entry" ]; then
    entry="$(sed -n 's/^name[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' "$work/gleam.toml")_test"
  fi
  if [ ! -f "$work/test/$hidden_module.gleam" ]; then
    echo "DISCOVERY FAILURE ($label): hidden test not present in test/ as $hidden_module.gleam" >&2
    return 1
  fi
  if [ -f "$work/test/$entry.gleam" ] && ! grep -q 'gleeunit\.main()' "$work/test/$entry.gleam"; then
    echo "DISCOVERY FAILURE ($label): test/$entry.gleam no longer calls gleeunit.main()" >&2
    return 1
  fi
  if grep -q 'No tests found!' "$log"; then
    echo "DISCOVERY FAILURE ($label): gleeunit reported no tests" >&2
    return 1
  fi
  expected=$(jq -r '(.visible_tests // 0) + (.hidden_tests // 0)' "$meta")
  passed=$(executed_tests "$log")
  if [ "$passed" -eq 0 ]; then
    echo "DISCOVERY FAILURE ($label): no test summary in output" >&2
    return 1
  fi
  if [ "$passed" -lt "$expected" ]; then
    echo "DISCOVERY FAILURE ($label): $passed tests executed, expected at least $expected" >&2
    return 1
  fi
  return 0
}

build_targets() { # $1 work, $2 meta, $3 log -> status
  local work="$1" meta="$2" log="$3" targets t status=0
  : > "$log"
  for t in $(jq -r '.targets[]?' "$meta"); do
    echo "== gleam build --target $t" >> "$log"
    ( cd "$work" && gleam build --target "$t" --no-print-progress ) >> "$log" 2>&1 || status=1
  done
  return $status
}

run_tests() { # $1 work, $2 meta, $3 log -> status
  local work="$1" meta="$2" log="$3" t status=0
  : > "$log"
  for t in $(jq -r '.targets[]?' "$meta"); do
    echo "== gleam test --target $t" >> "$log"
    ( cd "$work" && gleam test --target "$t" ) >> "$log" 2>&1 || status=1
  done
  return $status
}

run_case() { # $1 task, $2 condition
  local task="$1" condition="$2"
  local tdir="$tasks_dir/$task"
  local meta="$tdir/meta.json"
  local case_dir="$out/$condition/$task"
  local work="$case_dir/work"
  local prompt_file="$case_dir/prompt.txt"
  local feedback_file="$case_dir/feedback.txt"
  local metrics_file="$case_dir/agent-metrics.json"
  local log="$case_dir/last.log"
  local variant attempt started ended build_ok test_ok hidden_ok=false first_pass=false
  local builds=0 tests=0

  rm -rf "$case_dir"; mkdir -p "$case_dir"
  cp -R "$tdir/work" "$work"
  git -C "$work" init -q
  git -C "$work" add -A
  git -C "$work" -c user.email=bench@example.com -c user.name=bench commit -qm baseline
  : > "$feedback_file"; : > "$metrics_file"

  {
    cat "$tdir/prompt.md"
    case "$condition" in
      C|D)
        printf '\n\nYou may look up installed APIs:\n  %s sig <module>.<function>\n  %s find <name>\n  %s search <text>\n' \
          "$root/scripts/gleam-api" "$root/scripts/gleam-api" "$root/scripts/gleam-api" ;;
    esac
    if [ "$condition" = "D" ]; then
      printf '\nFollow the Gleam development skill at:\n  %s/skills/gleam-development/SKILL.md\n' "$root"
    fi
  } > "$prompt_file"

  started=$(date +%s)
  local attempts=1
  [ "$condition" != "A" ] && attempts="$max_attempts"

  for ((attempt = 1; attempt <= attempts; attempt++)); do
    variant=$(pick_variant "$condition" "$attempt" "$tdir")
    (
      cd "$work" && \
      BENCH_TASK="$task" BENCH_CONDITION="$condition" BENCH_ATTEMPT="$attempt" \
      BENCH_VARIANT="$variant" BENCH_PROMPT_FILE="$prompt_file" \
      BENCH_FEEDBACK_FILE="$feedback_file" \
      BENCH_SKILL_FILE="$root/skills/gleam-development/SKILL.md" \
      BENCH_DOCS_CMD="$root/scripts/gleam-api" BENCH_METRICS="$metrics_file" \
      "$agent"
    ) >> "$log" 2>&1 </dev/null
    local agent_status=$?
    echo "== attempt $attempt ($variant) agent exit $agent_status" >> "$log"

    build_ok=false; test_ok=false
    if build_targets "$work" "$meta" "$case_dir/build.log"; then build_ok=true; fi
    builds=$((builds + 1))
    if $build_ok; then
      if run_tests "$work" "$meta" "$case_dir/visible.log"; then test_ok=true; fi
      tests=$((tests + 1))
    fi

    # Evaluate hidden tests by injecting them, then remove them again. A build
    # failure is a failed attempt, not a discovery problem.
    hidden_ok=false
    if $build_ok; then
      cp "$tdir/hidden/$(jq -r '.hidden_module' "$meta").gleam" "$work/test/"
      if [ "${BENCH_BREAK_DISCOVERY:-}" = "missing" ]; then
        mkdir -p "$work/hidden_disabled"
        mv "$work/test/$(jq -r '.hidden_module' "$meta").gleam" "$work/hidden_disabled/"
      fi
      if [ "${BENCH_BREAK_DISCOVERY:-}" = "no_entry" ]; then
        entry="$(sed -n 's/^name[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' "$work/gleam.toml")_test"
        sed -i '' 's/gleeunit\.main()/Nil/' "$work/test/$entry.gleam" 2>/dev/null ||
          sed -i 's/gleeunit\.main()/Nil/' "$work/test/$entry.gleam"
      fi
      if run_tests "$work" "$meta" "$case_dir/hidden.log"; then
        verify_discovery "$work" "$meta" "$case_dir/hidden.log" "$task/$condition" && hidden_ok=true
      else
        verify_discovery "$work" "$meta" "$case_dir/hidden.log" "$task/$condition" || true
      fi
    fi
    if [ "$attempt" -eq 1 ]; then first_pass=$hidden_ok; fi
    rm -f "$work/test/$(jq -r '.hidden_module' "$meta").gleam"
    rm -rf "$work/hidden_disabled"

    if $hidden_ok; then break; fi
    {
      echo "Attempt $attempt did not pass the acceptance tests."
      echo "--- build ---"; tail -30 "$case_dir/build.log" 2>/dev/null
      echo "--- visible tests ---"; tail -20 "$case_dir/visible.log" 2>/dev/null
    } > "$feedback_file"
  done
  ended=$(date +%s)

  local modified unrelated duplicates regression files_read
  modified=$(git -C "$work" status --porcelain | awk '{print $2}' | grep -v '^build/' | wc -l | tr -d ' ')
  unrelated=$(
    git -C "$work" status --porcelain | awk '{print $2}' | grep -v '^build/' |
    while IFS= read -r f; do
      if ! jq -e --arg f "$f" '.touch | index($f) != null' "$meta" >/dev/null; then echo "$f"; fi
    done | wc -l | tr -d ' '
  )
  duplicates=0
  for symbol in $(jq -r '.forbidden[]?' "$meta"); do
    if grep -rqw -- "$symbol" "$work/src" 2>/dev/null; then duplicates=$((duplicates + 1)); fi
  done
  files_read=$(jq -r '.files_read // "null"' "$metrics_file" 2>/dev/null || echo null)
  regression=false
  $test_ok && regression=false || regression=true

  local attempts_used="$attempt"
  $hidden_ok || attempts_used="$attempts"
  jq -n \
    --arg task "$task" --arg condition "$condition" \
    --argjson first "$first_pass" --argjson final "$hidden_ok" \
    --argjson attempts_used "$attempts_used" --argjson builds "$builds" --argjson tests "$tests" \
    --argjson wall "$((ended - started))" --argjson modified "$modified" \
    --argjson unrelated "$unrelated" --argjson duplicates "$duplicates" \
    --argjson regression "$regression" --argjson files_read "$files_read" \
    '{task:$task, condition:$condition, first_attempt_pass:$first, final_pass:$final,
      attempts:$attempts_used, compiler_iterations:$builds, test_iterations:$tests,
      wall_clock_seconds:$wall, files_read:$files_read, files_modified:$modified,
      unrelated_changes:$unrelated, duplicated_implementations:$duplicates,
      behavioural_regression:$regression}' >> "$results_file"

  if $hidden_ok; then
    printf '%-18s %s  PASS  attempts=%s builds=%s files=%s unrelated=%s dups=%s\n' \
      "$task" "$condition" "$attempts_used" "$builds" "$modified" "$unrelated" "$duplicates"
  else
    printf '%-18s %s  FAIL  attempts=%s builds=%s files=%s unrelated=%s dups=%s\n' \
      "$task" "$condition" "$attempts_used" "$builds" "$modified" "$unrelated" "$duplicates"
  fi
}

task_list() {
  if [ -n "$selected" ]; then printf '%s\n' "$selected" | tr ',' '\n'; else ls "$tasks_dir"; fi
}

if $self_check; then
  echo "self-check: a hidden test that never executes must be refused"
  status=0
  for mode in missing no_entry; do
    BENCH_BREAK_DISCOVERY="$mode" "$0" --tasks word-frequency --conditions C --out "$out/selfcheck-$mode" \
      > "$out/selfcheck-$mode.log" 2>&1 || true
    if grep -q "DISCOVERY FAILURE" "$out/selfcheck-$mode.log"; then
      echo "  guard fired for break mode: $mode"
    else
      echo "  GUARD DID NOT FIRE for break mode: $mode" >&2
      status=1
    fi
  done
  if [ $status -ne 0 ]; then
    echo "self-check FAILED" >&2
    exit 1
  fi
  echo "self-check passed: discovery guard refuses runs whose tests did not execute"
  exit 0
fi

for task in $(task_list); do
  [ -f "$tasks_dir/$task/meta.json" ] || { echo "run.sh: unknown task $task" >&2; exit 2; }
  for condition in $(printf '%s\n' "$conditions" | tr ',' ' '); do
    run_case "$task" "$condition"
  done
done

jq -s --arg compiler "$compiler_version" --arg stdlib "$stdlib_version" --arg model "$model" \
  --argjson wall "$(( $(date +%s) - start_time ))" '
  { metadata: {model:$model, compiler:$compiler, stdlib:$stdlib, wall_clock_seconds:$wall,
               note:"Fixture agent results validate the harness, not the toolkit."},
    results: . }' "$results_file" > "$out/results.json"

echo
printf 'conditions: %s   model: %s   compiler: %s   stdlib: %s\n' "$conditions" "$model" "$compiler_version" "$stdlib_version"
jq -r '.results | group_by(.condition)[] |
  [.[0].condition,
   (map(select(.first_attempt_pass)) | length),
   (map(select(.final_pass)) | length),
   length] | @tsv' "$out/results.json" |
  awk -F'\t' 'BEGIN{printf "%-4s %-18s %-18s %s\n","cond","first-pass","final-pass","runs"}
              {printf "%-4s %-18s %-18s %s\n",$1,$2"/"$4,$3"/"$4,$4}'

if [ -n "$json_out" ]; then cp "$out/results.json" "$json_out"; fi
echo "results: $out/results.json"
