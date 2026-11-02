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

timeout_bin() {
  if [ -n "${BENCH_TIMEOUT_BIN+set}" ]; then printf '%s' "$BENCH_TIMEOUT_BIN"; return; fi
  command -v timeout 2>/dev/null || command -v gtimeout 2>/dev/null || true
}
TIMEOUT_BIN=$(timeout_bin)
if [ -z "$TIMEOUT_BIN" ]; then
  echo "run.sh: no timeout or gtimeout on PATH; agent attempts are unbounded (install coreutils, or set BENCH_TIMEOUT_BIN)" >&2
fi

command -v gleam >/dev/null || { echo "run.sh: gleam not on PATH" >&2; exit 2; }
command -v jq >/dev/null || { echo "run.sh: jq not on PATH" >&2; exit 2; }
[ -x "$agent" ] || { echo "run.sh: agent not executable: $agent" >&2; exit 2; }

compiler_version=$(gleam --version 2>/dev/null | head -1)
stdlib_version=$(sed -n 's/^ *{ name = "gleam_stdlib", version = "\([^"]*\)".*/\1/p' \
  "$tasks_dir"/*/work/manifest.toml 2>/dev/null | sort -u | paste -sd, -)

mkdir -p "$out"
out_real=$(cd "$out" && pwd -P)
root_real=$(cd "$root" && pwd -P)
case "$out_real/" in
  "$root_real"/*)
    echo "run.sh: --out must be outside the repository ($root_real); choose a directory under /tmp" >&2
    exit 2 ;;
esac
start_time=$(date +%s)
results_file="$out/results.jsonl"
: > "$results_file"

# Which recorded attempt is replayed. A never retries; B starts blind and
# repairs from compiler/test output; C and D start with lookup available.
pick_variant() { # $1 condition, $2 attempt, $3 task dir
  local condition="$1" attempt="$2" tdir="$3"
  if [ "$condition" = "A" ]; then echo baseline; return; fi
  if [ "$attempt" -eq 1 ]; then
    case "$condition" in
      B) echo baseline ;;
      *) [ -d "$tdir/agent/docs" ] && echo docs || echo baseline ;;
    esac
    return
  fi
  if [ "$attempt" -ge 3 ] && [ -d "$tdir/agent/repair" ]; then echo repair; return; fi
  [ -d "$tdir/agent/feedback" ] && { echo feedback; return; }
  [ -d "$tdir/agent/docs" ] && { echo docs; return; }
  echo baseline
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
verify_discovery() { # $1 work, $2 meta, $3 test log, $4 label, $5 visible-run count
  local work="$1" meta="$2" log="$3" label="$4" visible="$5"
  local hidden_module entry expected passed delta
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
  expected=$(jq -r '.hidden_tests // 0' "$meta")
  passed=$(executed_tests "$log")
  if [ "$passed" -eq 0 ]; then
    echo "DISCOVERY FAILURE ($label): no test summary after injecting hidden tests" >&2
    return 1
  fi
  # The hidden module's tests must show up as a delta over the visible run, so
  # an agent cannot satisfy the guard by adding passing tests of its own.
  delta=$((passed - visible))
  if [ "$delta" -lt "$expected" ]; then
    echo "DISCOVERY FAILURE ($label): hidden run executed $delta more tests than the visible run, expected at least $expected" >&2
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
  local builds=0 tests=0 visible_executed=0
  local envs=()

  rm -rf "$case_dir"; mkdir -p "$case_dir"
  # Stage the toolkit outside the repository tree so no path handed to the
  # agent leads back to benchmarks/tasks/*/hidden/.
  local stage="$out/.stage/$condition-$task"
  rm -rf "$stage"; mkdir -p "$stage"
  cp -R "$root/skills/gleam-development" "$stage/skill"
  cp "$root/scripts/gleam-api" "$stage/gleam-api"
  chmod +x "$stage/gleam-api"
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
          "$stage/gleam-api" "$stage/gleam-api" "$stage/gleam-api" ;;
    esac
    if [ "$condition" = "D" ]; then
      printf '\nFollow the Gleam development skill at:\n  %s/skill/SKILL.md\n' "$stage"
    fi
  } > "$prompt_file"

  started=$(date +%s)
  local attempts=1
  [ "$condition" != "A" ] && attempts="$max_attempts"

  for ((attempt = 1; attempt <= attempts; attempt++)); do
    variant=$(pick_variant "$condition" "$attempt" "$tdir")
    # Environment is built per condition: A never sees the toolkit.
    envs=(
      BENCH_TASK="$task" BENCH_CONDITION="$condition" BENCH_ATTEMPT="$attempt"
      BENCH_VARIANT="$variant" BENCH_PROMPT_FILE="$prompt_file"
      BENCH_FEEDBACK_FILE="$feedback_file" BENCH_METRICS="$metrics_file"
    )
    case "$condition" in
      C|D) envs+=(BENCH_DOCS_CMD="$stage/gleam-api") ;;
    esac
    if [ "$condition" = "D" ]; then
      envs+=(BENCH_SKILL_FILE="$stage/skill/SKILL.md")
    fi
    local agent_status
    if [ -n "$TIMEOUT_BIN" ]; then
      ( cd "$work" && env "${envs[@]}" "$TIMEOUT_BIN" "${BENCH_AGENT_TIMEOUT:-600}" "$agent" ) >> "$log" 2>&1 </dev/null
    else
      ( cd "$work" && env "${envs[@]}" "$agent" ) >> "$log" 2>&1 </dev/null
    fi
    agent_status=$?
    echo "== attempt $attempt ($variant) agent exit $agent_status" >> "$log"
    if [ "$agent_status" -eq 124 ]; then
      echo "== attempt $attempt timed out after ${BENCH_AGENT_TIMEOUT:-600}s" >> "$log"
    fi

    build_ok=false; test_ok=false
    visible_executed=0
    if build_targets "$work" "$meta" "$case_dir/build.log"; then build_ok=true; fi
    builds=$((builds + 1))
    if $build_ok; then
      if run_tests "$work" "$meta" "$case_dir/visible.log"; then test_ok=true; fi
      visible_executed=$(executed_tests "$case_dir/visible.log")
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
      if [ "${BENCH_BREAK_DISCOVERY:-}" = "hollow" ]; then
        printf 'pub fn placeholder_test() {\n  Nil\n}\n' > "$work/test/$(jq -r '.hidden_module' "$meta").gleam"
      fi
      if [ "${BENCH_BREAK_DISCOVERY:-}" = "no_entry" ]; then
        entry="$(sed -n 's/^name[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' "$work/gleam.toml")_test"
        sed -i '' 's/gleeunit\.main()/Nil/' "$work/test/$entry.gleam" 2>/dev/null ||
          sed -i 's/gleeunit\.main()/Nil/' "$work/test/$entry.gleam"
      fi
      if run_tests "$work" "$meta" "$case_dir/hidden.log"; then
        verify_discovery "$work" "$meta" "$case_dir/hidden.log" "$task/$condition" "$visible_executed" && hidden_ok=true
      else
        verify_discovery "$work" "$meta" "$case_dir/hidden.log" "$task/$condition" "$visible_executed" || true
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

  local modified unrelated duplicates regression files_read changed
  # ls-files handles paths with spaces and excludes ignored build output.
  changed=$(git -C "$work" ls-files -m -o --exclude-standard | grep -v '^build/' || true)
  modified=$(printf '%s\n' "$changed" | grep -c . || true)
  unrelated=$(
    printf '%s\n' "$changed" |
    while IFS= read -r f; do
      [ -z "$f" ] && continue
      if ! jq -e --arg f "$f" '.touch | index($f) != null' "$meta" >/dev/null; then echo "$f"; fi
    done | grep -c . || true
  )
  duplicates=0
  for symbol in $(jq -r '.forbidden[]?' "$meta"); do
    if grep -rqw -- "$symbol" "$work/src" 2>/dev/null; then duplicates=$((duplicates + 1)); fi
  done
  files_read=$(jq -r '.files_read // "null"' "$metrics_file" 2>/dev/null)
  # An absent or empty metrics file, or a non-numeric value, means "not reported".
  case "$files_read" in
    ""|null|*[!0-9]*) files_read=null ;;
  esac
  regression=false
  $test_ok && regression=false || regression=true

  local attempts_used="$attempt"
  $hidden_ok || attempts_used="$attempts"
  jq -c -n \
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
  echo "self-check: conditions must not leak the toolkit and the guard must refuse unexecuted tests"
  status=0

  probe=$(mktemp)
  cat > "$probe" <<'PROBE'
#!/usr/bin/env bash
env | grep '^BENCH_' | sort > "${BENCH_PROBE_OUT:?}"
PROBE
  chmod +x "$probe"

  probe_condition() { # $1 condition
    local condition="$1"
    local probe_out="$out/probe-$condition.txt"
    BENCH_PROBE_OUT="$probe_out" "$0" --tasks word-frequency --conditions "$condition" \
      --agent "$probe" --out "$out/selfcheck-probe-$condition" >/dev/null 2>&1 || true
    cat "$probe_out" 2>/dev/null
  }

  a_env=$(probe_condition A)
  if printf '%s\n' "$a_env" | grep -q '^BENCH_\(DOCS_CMD\|SKILL_FILE\)='; then
    echo "  BASELINE LEAK: condition A received toolkit paths" >&2
    status=1
  else
    echo "  condition A receives no toolkit paths"
  fi

  c_env=$(probe_condition C)
  if printf '%s\n' "$c_env" | grep -q '^BENCH_DOCS_CMD=' &&
     ! printf '%s\n' "$c_env" | grep -q '^BENCH_SKILL_FILE='; then
    echo "  condition C receives the lookup command only"
  else
    echo "  CONDITION C MISMATCH" >&2
    status=1
  fi

  d_env=$(probe_condition D)
  if printf '%s\n' "$d_env" | grep -q '^BENCH_SKILL_FILE=' &&
     printf '%s\n' "$d_env" | grep -q '^BENCH_DOCS_CMD='; then
    echo "  condition D receives the skill and the lookup command"
  else
    echo "  CONDITION D MISMATCH" >&2
    status=1
  fi

  if printf '%s\n%s\n%s\n' "$a_env" "$c_env" "$d_env" | grep -F -q "$root"; then
    echo "  PATH LEAK: an agent was handed a path inside the repository" >&2
    status=1
  else
    echo "  no agent environment contains the repository root"
  fi

  for mode in missing no_entry hollow; do
    BENCH_BREAK_DISCOVERY="$mode" "$0" --tasks word-frequency --conditions C --out "$out/selfcheck-$mode" \
      > "$out/selfcheck-$mode.log" 2>&1 || true
    if grep -q "DISCOVERY FAILURE" "$out/selfcheck-$mode.log"; then
      echo "  guard fired for break mode: $mode"
    else
      echo "  GUARD DID NOT FIRE for break mode: $mode" >&2
      status=1
    fi
  done

  slow=$(mktemp)
  printf '#!/usr/bin/env bash\nsleep 5\n' > "$slow"
  chmod +x "$slow"
  if [ -n "$TIMEOUT_BIN" ]; then
    BENCH_AGENT_TIMEOUT=1 "$0" --tasks word-frequency --conditions B --agent "$slow" \
      --max-attempts 1 --out "$out/selfcheck-timeout" >/dev/null 2>&1 || true
    if grep -q "timed out" "$out/selfcheck-timeout/B/word-frequency/last.log"; then
      echo "  agent timeout is recorded via $TIMEOUT_BIN"
    else
      echo "  AGENT TIMEOUT NOT RECORDED" >&2
      status=1
    fi
  else
    echo "  agent timeout probe skipped: no timeout or gtimeout on PATH"
  fi

  # With the timeout explicitly disabled the run must still complete and say so.
  BENCH_TIMEOUT_BIN= BENCH_AGENT_TIMEOUT=1 "$0" --tasks word-frequency --conditions A \
    --agent "$slow" --max-attempts 1 --out "$out/selfcheck-no-timeout" \
    > "$out/selfcheck-no-timeout.log" 2>&1 || true
  if grep -q "attempts are unbounded" "$out/selfcheck-no-timeout.log"; then
    echo "  missing timeout binary is reported, not silent"
  else
    echo "  MISSING TIMEOUT NOT REPORTED" >&2
    status=1
  fi
  rm -f "$probe" "$slow"

  if [ $status -ne 0 ]; then
    echo "self-check FAILED" >&2
    exit 1
  fi
  echo "self-check passed: conditions are separated, paths are staged, and the discovery guard refuses runs whose tests did not execute"
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
