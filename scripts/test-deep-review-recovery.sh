#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNNER="$ROOT/skills/deep-review/scripts/deep-review.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/deep-review-recovery-test.XXXXXX")"
cleanup() {
  jobs -pr 2>/dev/null | xargs kill -TERM 2>/dev/null || true
  rm -rf "$TMP"
}
trap cleanup EXIT INT TERM

mkdir -p "$TMP/repo" "$TMP/bin"
cd "$TMP/repo"
git init -q -b main 2>/dev/null || { git init -q; git checkout -qb main; }
git config user.email test@example.com
git config user.name "Deep Review Test"
printf 'hello\n' > target.txt
git add target.txt
git commit -qm init

cat >"$TMP/bin/codex" <<'EOF_CODEX'
#!/usr/bin/env bash
set -u
prompt=""
for arg in "$@"; do prompt="$arg"; done
run_dir="${DEEP_REVIEW_ACTIVE_RUN_DIR:?}"

if printf '%s' "$prompt" | grep -q 'specialized READ-ONLY code analysis agent'; then
  target="$(printf '%s\n' "$prompt" | sed -n 's/^Write your complete Markdown findings to: //p' | head -1)"
  printf 'review:%s\n' "$target" >>"${FAKE_CALL_LOG:?}"
  if [ "${FAKE_BLOCK_ALL:-0}" = 1 ] || { [ "${FAKE_BLOCK_SILENT:-0}" = 1 ] && printf '%s' "$target" | grep -q 'silent-failure-hunter.md'; }; then
    printf '%s\n' "$$" >"${FAKE_BLOCK_MARKER:?}.pid"
    : >"${FAKE_BLOCK_MARKER:?}"
    trap 'exit 143' TERM INT HUP
    while :; do sleep 1; done
  fi
  printf '# Findings\n\nNo findings.\n' >"$target"
elif printf '%s' "$prompt" | grep -q 'synthesis agent for a multi-agent code review'; then
  echo synth >>"${FAKE_CALL_LOG:?}"
  printf '# Report\n' >"$run_dir/REPORT.md"
elif printf '%s' "$prompt" | grep -q 'extract every distinct code-review finding'; then
  echo extract >>"${FAKE_CALL_LOG:?}"
  mkdir -p "$run_dir/findings"
  echo 0 >"$run_dir/findings/count.txt"
elif printf '%s' "$prompt" | grep -q 'final code-review triage editor'; then
  echo final >>"${FAKE_CALL_LOG:?}"
  printf '# Final\n\nNo findings.\n' >"$run_dir/FINAL.md"
else
  echo unknown >>"${FAKE_CALL_LOG:?}"
fi
EOF_CODEX
chmod +x "$TMP/bin/codex"

wait_for_file() {
  file="$1"
  n=0
  while [ ! -e "$file" ] && [ "$n" -lt 100 ]; do
    sleep 0.1
    n=$((n + 1))
  done
  [ -e "$file" ]
}

# Interruption recovery: completed reviewer output must not be recomputed.
STATE="$TMP/state-recovery"
CALLS="$TMP/calls-recovery"
BLOCK="$TMP/block-recovery"
: >"$CALLS"
PATH="$TMP/bin:$PATH" FAKE_CALL_LOG="$CALLS" FAKE_BLOCK_SILENT=1 FAKE_BLOCK_MARKER="$BLOCK" \
  DEEP_REVIEW_PROVIDER=codex DEEP_REVIEW_STATE_DIR="$STATE" \
  bash "$RUNNER" --max-concurrent 1 target.txt code errors >"$TMP/first.out" 2>"$TMP/first.err" &
first_pid=$!
wait_for_file "$BLOCK"
kill -TERM "$first_pid"
set +e
wait "$first_pid"
first_rc=$?
set -e
[ "$first_rc" -ne 0 ]

blocked_pid="$(cat "$BLOCK.pid")"
sleep 0.2
! kill -0 "$blocked_pid" 2>/dev/null

grep -q '^interrupted$' "$(find "$STATE" -name status | head -1)"
PATH="$TMP/bin:$PATH" FAKE_CALL_LOG="$CALLS" DEEP_REVIEW_PROVIDER=codex DEEP_REVIEW_STATE_DIR="$STATE" \
  bash "$RUNNER" --max-concurrent 1 target.txt code errors >"$TMP/second.out" 2>"$TMP/second.err"
grep -q 'Resuming interrupted review run:' "$TMP/second.err"
[ "$(grep -c 'code-reviewer.md' "$CALLS")" -eq 1 ]
[ "$(grep -c 'silent-failure-hunter.md' "$CALLS")" -eq 2 ]
latest="$(PATH="$TMP/bin:$PATH" DEEP_REVIEW_STATE_DIR="$STATE" bash "$RUNNER" --latest-artifacts)"
[ -s "$latest/FINAL.md" ]
grep -q '^completed$' "$latest/status"

# Simultaneous identical runs must not share a live recovery directory.
STATE_SIM="$TMP/state-simultaneous"
CALLS_SIM="$TMP/calls-simultaneous"
BLOCK_A="$TMP/block-a"
BLOCK_B="$TMP/block-b"
: >"$CALLS_SIM"
PATH="$TMP/bin:$PATH" FAKE_CALL_LOG="$CALLS_SIM" FAKE_BLOCK_ALL=1 FAKE_BLOCK_MARKER="$BLOCK_A" \
  DEEP_REVIEW_PROVIDER=codex DEEP_REVIEW_STATE_DIR="$STATE_SIM" \
  bash "$RUNNER" --max-concurrent 1 target.txt code >"$TMP/a.out" 2>"$TMP/a.err" &
pid_a=$!
wait_for_file "$BLOCK_A"
PATH="$TMP/bin:$PATH" FAKE_CALL_LOG="$CALLS_SIM" FAKE_BLOCK_ALL=1 FAKE_BLOCK_MARKER="$BLOCK_B" \
  DEEP_REVIEW_PROVIDER=codex DEEP_REVIEW_STATE_DIR="$STATE_SIM" \
  bash "$RUNNER" --max-concurrent 1 target.txt code >"$TMP/b.out" 2>"$TMP/b.err" &
pid_b=$!
wait_for_file "$BLOCK_B"
[ "$(find "$STATE_SIM" -type d -name 'run-*' | wc -l | tr -d ' ')" -eq 2 ]
kill -TERM "$pid_a" "$pid_b" 2>/dev/null || true
set +e
wait "$pid_a"
wait "$pid_b"
set -e

# Memory pressure must reduce concurrency rather than honoring a dangerous fan-out.
STATE_MEM="$TMP/state-memory"
CALLS_MEM="$TMP/calls-memory"
: >"$CALLS_MEM"
PATH="$TMP/bin:$PATH" FAKE_CALL_LOG="$CALLS_MEM" DEEP_REVIEW_PROVIDER=codex DEEP_REVIEW_STATE_DIR="$STATE_MEM" \
  DEEP_REVIEW_MEMORY_RESERVE_MB=999999999 \
  bash "$RUNNER" --max-concurrent 8 target.txt code >"$TMP/memory.out" 2>"$TMP/memory.err"
grep -q 'Memory guard: limiting concurrency from 8 to 1' "$TMP/memory.err"
plan="$(find "$STATE_MEM" -name resource-plan.txt | head -1)"
grep -q '^safe_concurrency=1$' "$plan"

# Saved-run discovery should work without a provider invocation.
PATH="$TMP/bin:$PATH" DEEP_REVIEW_STATE_DIR="$STATE_MEM" bash "$RUNNER" --list-runs | grep -q 'completed'

echo "deep-review recovery/resource smoke test passed"
