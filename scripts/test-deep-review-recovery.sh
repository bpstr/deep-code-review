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
work_dir="${DEEP_REVIEW_ACTIVE_WORK_DIR:?}"

block_here() {
  printf '%s\n' "$$" >"${FAKE_BLOCK_MARKER:?}.pid"
  : >"${FAKE_BLOCK_MARKER:?}"
  trap 'exit 143' TERM INT HUP
  while :; do sleep 1; done
}

if printf '%s' "$prompt" | grep -q 'specialized READ-ONLY code analysis agent'; then
  target="$(printf '%s\n' "$prompt" | sed -n 's/^Write your complete Markdown findings to: //p' | head -1)"
  printf 'review:%s\n' "$target" >>"${FAKE_CALL_LOG:?}"
  if [ "${FAKE_FAIL_CODE_ONCE:-0}" = 1 ] && printf '%s' "$target" | grep -q 'code-reviewer.md' && [ ! -e "${FAKE_FAIL_MARKER:?}" ]; then
    : >"${FAKE_FAIL_MARKER:?}"
    exit 42
  fi
  if [ "${FAKE_BLOCK_ALL:-0}" = 1 ] || { [ "${FAKE_BLOCK_SILENT:-0}" = 1 ] && printf '%s' "$target" | grep -q 'silent-failure-hunter.md'; }; then
    block_here
  fi
  printf '# Findings\n\nNo findings.\n' >"$target"
elif printf '%s' "$prompt" | grep -q 'synthesis agent for a multi-agent code review'; then
  echo synth >>"${FAKE_CALL_LOG:?}"
  printf '# Report\n' >"$work_dir/REPORT.md"
elif printf '%s' "$prompt" | grep -q 'extract every distinct code-review finding'; then
  echo extract >>"${FAKE_CALL_LOG:?}"
  mkdir -p "$work_dir/findings"
  echo 0 >"$work_dir/findings/count.txt"
elif printf '%s' "$prompt" | grep -q 'final code-review triage editor'; then
  echo final >>"${FAKE_CALL_LOG:?}"
  if [ "${FAKE_BLOCK_FINAL:-0}" = 1 ]; then block_here; fi
  printf '# Final\n\nNo findings.\n' >"$work_dir/FINAL.md"
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

# Interruption recovery: completed reviewer output must be checkpointed outside the
# provider's temporary sandbox and must not be recomputed.
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
run="$(find "$STATE" -type d -name 'run-*' | head -1)"
grep -q '^interrupted$' "$run/status"
[ -s "$run/checkpoints/data/code-reviewer.md" ]
grep -q '/deep-review-work\.' "$CALLS"
! grep -q "$STATE.*code-reviewer.md" "$CALLS"

PATH="$TMP/bin:$PATH" FAKE_CALL_LOG="$CALLS" DEEP_REVIEW_PROVIDER=codex DEEP_REVIEW_STATE_DIR="$STATE" \
  bash "$RUNNER" --max-concurrent 1 target.txt code errors >"$TMP/second.out" 2>"$TMP/second.err"
grep -q 'Resuming interrupted review run:' "$TMP/second.err"
[ "$(grep -c 'code-reviewer.md' "$CALLS")" -eq 1 ]
[ "$(grep -c 'silent-failure-hunter.md' "$CALLS")" -eq 2 ]
latest="$(PATH="$TMP/bin:$PATH" DEEP_REVIEW_STATE_DIR="$STATE" bash "$RUNNER" --latest-artifacts)"
[ -s "$latest/FINAL.md" ]
grep -q '^completed$' "$latest/status"

# If an upstream reviewer failed before synthesis and later succeeds on resume, every
# checkpoint derived from the old reviewer set must be regenerated rather than reused.
STATE_DEP="$TMP/state-dependencies"
CALLS_DEP="$TMP/calls-dependencies"
BLOCK_DEP="$TMP/block-dependencies"
FAIL_DEP="$TMP/fail-dependencies"
: >"$CALLS_DEP"
PATH="$TMP/bin:$PATH" FAKE_CALL_LOG="$CALLS_DEP" FAKE_FAIL_CODE_ONCE=1 FAKE_FAIL_MARKER="$FAIL_DEP" \
  FAKE_BLOCK_FINAL=1 FAKE_BLOCK_MARKER="$BLOCK_DEP" \
  DEEP_REVIEW_PROVIDER=codex DEEP_REVIEW_STATE_DIR="$STATE_DEP" \
  bash "$RUNNER" --max-concurrent 1 target.txt code errors >"$TMP/dep-first.out" 2>"$TMP/dep-first.err" &
dep_pid=$!
wait_for_file "$BLOCK_DEP"
[ "$(grep -c '^synth$' "$CALLS_DEP")" -eq 1 ]
kill -TERM "$dep_pid"
set +e
wait "$dep_pid"
set -e

PATH="$TMP/bin:$PATH" FAKE_CALL_LOG="$CALLS_DEP" FAKE_FAIL_CODE_ONCE=1 FAKE_FAIL_MARKER="$FAIL_DEP" \
  DEEP_REVIEW_PROVIDER=codex DEEP_REVIEW_STATE_DIR="$STATE_DEP" \
  bash "$RUNNER" --max-concurrent 1 target.txt code errors >"$TMP/dep-second.out" 2>"$TMP/dep-second.err"
grep -q 'Resuming interrupted review run:' "$TMP/dep-second.err"
[ "$(grep -c 'code-reviewer.md' "$CALLS_DEP")" -eq 2 ]
[ "$(grep -c '^synth$' "$CALLS_DEP")" -eq 2 ]
[ "$(grep -c '^extract$' "$CALLS_DEP")" -eq 2 ]
[ "$(grep -c '^final$' "$CALLS_DEP")" -eq 2 ]

# Simultaneous identical runs must get distinct live run directories. Give this test
# enough global slots so it tests isolation rather than the aggregate memory gate below.
STATE_SIM="$TMP/state-simultaneous"
CALLS_SIM="$TMP/calls-simultaneous"
BLOCK_A="$TMP/block-a"
BLOCK_B="$TMP/block-b"
: >"$CALLS_SIM"
PATH="$TMP/bin:$PATH" FAKE_CALL_LOG="$CALLS_SIM" FAKE_BLOCK_ALL=1 FAKE_BLOCK_MARKER="$BLOCK_A" \
  DEEP_REVIEW_PROVIDER=codex DEEP_REVIEW_STATE_DIR="$STATE_SIM" \
  DEEP_REVIEW_MEMORY_RESERVE_MB=0 DEEP_REVIEW_MEMORY_PER_WORKER_MB=1 \
  bash "$RUNNER" --max-concurrent 2 target.txt code >"$TMP/a.out" 2>"$TMP/a.err" &
pid_a=$!
wait_for_file "$BLOCK_A"
run_a="$(find "$STATE_SIM" -type d -name 'run-*' | head -1)"
[ -f "$run_a/.lock" ]
[ "$(wc -l <"$run_a/.lock" | tr -d ' ')" -eq 2 ]
PATH="$TMP/bin:$PATH" FAKE_CALL_LOG="$CALLS_SIM" FAKE_BLOCK_ALL=1 FAKE_BLOCK_MARKER="$BLOCK_B" \
  DEEP_REVIEW_PROVIDER=codex DEEP_REVIEW_STATE_DIR="$STATE_SIM" \
  DEEP_REVIEW_MEMORY_RESERVE_MB=0 DEEP_REVIEW_MEMORY_PER_WORKER_MB=1 \
  bash "$RUNNER" --max-concurrent 2 target.txt code >"$TMP/b.out" 2>"$TMP/b.err" &
pid_b=$!
wait_for_file "$BLOCK_B"
[ "$(find "$STATE_SIM" -type d -name 'run-*' | wc -l | tr -d ' ')" -eq 2 ]
kill -TERM "$pid_a" "$pid_b" 2>/dev/null || true
set +e
wait "$pid_a"
wait "$pid_b"
set -e

# Untracked path contents are part of the recovery identity. Changing an untracked file
# after an interrupted path review must start a new run rather than reuse stale output.
STATE_FP="$TMP/state-fingerprint"
CALLS_FP="$TMP/calls-fingerprint"
BLOCK_FP="$TMP/block-fingerprint"
: >"$CALLS_FP"
printf 'first\n' > loose.txt
PATH="$TMP/bin:$PATH" FAKE_CALL_LOG="$CALLS_FP" FAKE_BLOCK_ALL=1 FAKE_BLOCK_MARKER="$BLOCK_FP" \
  DEEP_REVIEW_PROVIDER=codex DEEP_REVIEW_STATE_DIR="$STATE_FP" \
  bash "$RUNNER" --max-concurrent 1 loose.txt code >"$TMP/fp-first.out" 2>"$TMP/fp-first.err" &
fp_pid=$!
wait_for_file "$BLOCK_FP"
kill -TERM "$fp_pid"
set +e
wait "$fp_pid"
set -e
printf 'second\n' > loose.txt
PATH="$TMP/bin:$PATH" FAKE_CALL_LOG="$CALLS_FP" DEEP_REVIEW_PROVIDER=codex DEEP_REVIEW_STATE_DIR="$STATE_FP" \
  bash "$RUNNER" --max-concurrent 1 loose.txt code >"$TMP/fp-second.out" 2>"$TMP/fp-second.err"
grep -q 'Starting durable review run:' "$TMP/fp-second.err"
! grep -q 'Resuming interrupted review run:' "$TMP/fp-second.err"
[ "$(find "$STATE_FP" -type d -name 'run-*' | wc -l | tr -d ' ')" -eq 2 ]
rm -f loose.txt

# Aggregate memory protection: two independent review runs share machine-level provider
# slots, so individually safe runs cannot multiply into an OOM-sized combined fan-out.
STATE_GLOBAL="$TMP/state-global"
CALLS_GLOBAL="$TMP/calls-global"
BLOCK_GA="$TMP/block-global-a"
BLOCK_GB="$TMP/block-global-b"
: >"$CALLS_GLOBAL"
PATH="$TMP/bin:$PATH" FAKE_CALL_LOG="$CALLS_GLOBAL" FAKE_BLOCK_ALL=1 FAKE_BLOCK_MARKER="$BLOCK_GA" \
  DEEP_REVIEW_PROVIDER=codex DEEP_REVIEW_STATE_DIR="$STATE_GLOBAL" \
  DEEP_REVIEW_MEMORY_RESERVE_MB=999999999 \
  bash "$RUNNER" --max-concurrent 8 target.txt code >"$TMP/ga.out" 2>"$TMP/ga.err" &
pid_ga=$!
wait_for_file "$BLOCK_GA"
PATH="$TMP/bin:$PATH" FAKE_CALL_LOG="$CALLS_GLOBAL" FAKE_BLOCK_ALL=1 FAKE_BLOCK_MARKER="$BLOCK_GB" \
  DEEP_REVIEW_PROVIDER=codex DEEP_REVIEW_STATE_DIR="$STATE_GLOBAL" \
  DEEP_REVIEW_MEMORY_RESERVE_MB=999999999 \
  bash "$RUNNER" --max-concurrent 8 target.txt code >"$TMP/gb.out" 2>"$TMP/gb.err" &
pid_gb=$!
sleep 1
[ ! -e "$BLOCK_GB" ]
kill -TERM "$pid_ga"
set +e
wait "$pid_ga"
set -e
wait_for_file "$BLOCK_GB"
kill -TERM "$pid_gb"
set +e
wait "$pid_gb"
set -e

# Memory pressure must also reduce per-run concurrency and record the decision.
STATE_MEM="$TMP/state-memory"
CALLS_MEM="$TMP/calls-memory"
: >"$CALLS_MEM"
PATH="$TMP/bin:$PATH" FAKE_CALL_LOG="$CALLS_MEM" DEEP_REVIEW_PROVIDER=codex DEEP_REVIEW_STATE_DIR="$STATE_MEM" \
  DEEP_REVIEW_MEMORY_RESERVE_MB=999999999 \
  bash "$RUNNER" --max-concurrent 8 target.txt code >"$TMP/memory.out" 2>"$TMP/memory.err"
grep -q 'Memory guard: limiting concurrency from 8 to 1' "$TMP/memory.err"
plan="$(find "$STATE_MEM" -name resource-plan.txt | head -1)"
grep -q '^safe_concurrency=1$' "$plan"
grep -q '^global_provider_slots=1$' "$plan"

# Saved-run discovery should work without a provider invocation.
PATH="$TMP/bin:$PATH" DEEP_REVIEW_STATE_DIR="$STATE_MEM" bash "$RUNNER" --list-runs | grep -q 'completed'

echo "deep-review recovery/resource smoke test passed"