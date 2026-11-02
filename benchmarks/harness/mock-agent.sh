#!/usr/bin/env bash
# Fixture agent: replays a recorded attempt for a task instead of calling a
# model. It exists so the harness can be exercised end to end without paid API
# access. It is NOT evidence about model quality.
#
# Replays $BENCH_TASK/agent/$BENCH_VARIANT/: every file in that directory is
# copied over the work directory at the same relative path.
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../.." && pwd)
variant_dir="$root/benchmarks/tasks/${BENCH_TASK:?}/agent/${BENCH_VARIANT:?}"

if [ ! -d "$variant_dir" ]; then
  echo "mock-agent: no recorded attempt at $variant_dir" >&2
  exit 1
fi

copied=0
while IFS= read -r rel; do
  mkdir -p "$(dirname "$rel")"
  cp "$variant_dir/$rel" "$rel"
  copied=$((copied + 1))
done < <(cd "$variant_dir" && find . -type f | sed 's|^\./||' | sort)

# Tokens are null: a fixture has no model. files_read counts the prompt and the
# files this fixture replaced, nothing more.
jq -n --argjson read "$((copied + 1))" --argjson written "$copied" \
  '{files_read:$read, files_written:$written, tokens:null, model:"fixture"}' \
  > "${BENCH_METRICS:?}"

echo "mock-agent: replayed $BENCH_TASK/$BENCH_VARIANT ($copied files, attempt $BENCH_ATTEMPT)"
