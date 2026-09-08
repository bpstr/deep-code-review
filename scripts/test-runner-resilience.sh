#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNNER="$ROOT/skills/deep-review/scripts/deep-review.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/deep-review-resilience.XXXXXX")"
cleanup() {
  pids="$(jobs -pr 2>/dev/null || true)"
  [ -z "$pids" ] || kill $pids 2>/dev/null || true
  rm -rf "$TMP"
}
trap cleanup EXIT INT TERM

mkdir -p "$TMP/skill/skills/deep-review/scripts" "$TMP/skill/skills/deep-review/agents" "$TMP/skill/skills/deep-review/support" "$TMP/bin" "$TMP/repo"
cp "$RUNNER" "$TMP/skill/skills/deep-review/scripts/deep-review.sh"
for agent in code-reviewer silent-failure-hunter synthesizer accessibility-scanner; do
  printf '# %s\n' "$agent" >"$TMP/skill/skills/deep-review/agents/$agent.md"
done
printf '# stack profiler\n' >"$TMP/skill/skills/deep-review/support/stack-profiler.md"

cat >"$TMP/bin/codex" <<'EOF_FAKE'
#!/usr/bin/env bash
set -e
prompt=""
for arg in "$@"; do prompt="$arg"; done
counter_dir="${FAKE_COUNTER_DIR:?}"
mkdir -p "$counter_dir"
inc() {
  file="$counter_dir/$1.count"
  count=0
  [ ! -f "$file" ] || count="$(cat "$file")"
  count=$((count + 1))
  printf '%s\n' "$count" >"$file"
}
write_after_prefix() {
  prefix="$1"
  body="$2"
  output="$(printf '%s\n' "$prompt" | sed -n "s#^$prefix##p" | tail -1)"
  [ -n "$output" ] || return 1
  mkdir -p "$(dirname "$output")"
  printf '%s\n' "$body" >"$output"
}
case "$prompt" in
  *"Read your analysis instructions from:"*"code-reviewer.md"*)
    inc code
    [ "${FAKE_SLEEP_CODE:-0}" -le 0 ] || sleep "$FAKE_SLEEP_CODE"
    write_after_prefix 'Write your complete Markdown findings to: ' '# code complete'
    ;;
  *"Read your analysis instructions from:"*"silent-failure-hunter.md"*)
    inc errors
    if [ ! -f "$counter_dir/errors-started" ]; then
      touch "$counter_dir/errors-started"
      [ "${FAKE_FIRST_ERROR_SLEEP:-0}" -le 0 ] || sleep "$FAKE_FIRST_ERROR_SLEEP"
    fi
    write_after_prefix 'Write your complete Markdown findings to: ' '# errors complete'
    ;;
  *"synthesis agent"*)
    inc synth
    write_after_prefix 'Deduplicate findings, preserve evidence and classification, and write the merged report to: ' '# report'
    ;;
  *"extract every distinct"*)
    inc extract
    output="$(printf '%s\n' "$prompt" | sed -n 's#^Write only the integer finding count to ##p' | sed 's/\.$//' | tail -1)"
    mkdir -p "$(dirname "$output")"
    printf '0\n' >"$output"
    ;;
  *"final code-review triage editor"*)
    inc final
    write_after_prefix 'Write the final report to: ' '# final'
    ;;
  *)
    echo "unexpected fake Codex prompt" >&2
    exit 2
    ;;
esac
EOF_FAKE
chmod +x "$TMP/bin/codex"

cd "$TMP/repo"
git init -q
git config user.email test@example.com
git config user.name Test
git checkout -qb main
printf 'one\n' >app.txt
git add app.txt
git commit -qm init
git checkout -qb feature
printf 'two\n' >>app.txt
git add app.txt
git commit -qm change

export PATH="$TMP/bin:$PATH"

# A TERM after the first reviewer must preserve its checkpoint; restart reruns only
# the reviewer that was actually in flight.
mkdir -p "$TMP/recovery-counters" "$TMP/recovery-state"
export FAKE_COUNTER_DIR="$TMP/recovery-counters"
export FAKE_FIRST_ERROR_SLEEP=30
export FAKE_SLEEP_CODE=0
export DEEP_REVIEW_STATE_DIR="$TMP/recovery-state"
unset DEEP_REVIEW_AVAILABLE_MEMORY_MB_OVERRIDE DEEP_REVIEW_MIN_FREE_MB || true
set +e
bash "$TMP/skill/skills/deep-review/scripts/deep-review.sh" --provider codex --max-concurrent 1 code errors >"$TMP/first.out" 2>"$TMP/first.err" &
runner_pid=$!
i=0
while [ "$i" -lt 100 ] && [ ! -f "$TMP/recovery-counters/errors-started" ]; do
  i=$((i + 1))
  sleep 0.1
done
kill -TERM "$runner_pid"
wait "$runner_pid"
first_rc=$?
set -e
[ "$first_rc" -ne 0 ]
[ "$(cat "$TMP/recovery-counters/code.count")" = 1 ]
run_dir="$(dirname "$(find "$TMP/recovery-state" -type f -name request-key -print | head -1)")"
[ -f "$run_dir/checkpoints/reviewer-code-reviewer.done" ]
[ ! -f "$run_dir/checkpoints/reviewer-silent-failure-hunter.done" ]
FAKE_FIRST_ERROR_SLEEP=0 bash "$TMP/skill/skills/deep-review/scripts/deep-review.sh" --provider codex --max-concurrent 1 code errors >"$TMP/resume.out" 2>"$TMP/resume.err"
[ "$(cat "$TMP/recovery-counters/code.count")" = 1 ]
[ "$(cat "$TMP/recovery-counters/errors.count")" = 2 ]
[ -f "$run_dir/completed" ]
grep -q '^# final' "$TMP/resume.out"

# Two identical live requests must get independent run directories rather than
# sharing or clobbering an active checkpoint set.
mkdir -p "$TMP/concurrent-counters" "$TMP/concurrent-state"
export FAKE_COUNTER_DIR="$TMP/concurrent-counters"
export FAKE_SLEEP_CODE=2
export FAKE_FIRST_ERROR_SLEEP=0
export DEEP_REVIEW_STATE_DIR="$TMP/concurrent-state"
bash "$TMP/skill/skills/deep-review/scripts/deep-review.sh" --provider codex --max-concurrent 1 code >"$TMP/concurrent-1.out" 2>"$TMP/concurrent-1.err" &
first_pid=$!
sleep 0.3
bash "$TMP/skill/skills/deep-review/scripts/deep-review.sh" --provider codex --max-concurrent 1 code >"$TMP/concurrent-2.out" 2>"$TMP/concurrent-2.err" &
second_pid=$!
wait "$first_pid"
wait "$second_pid"
[ "$(find "$TMP/concurrent-state" -type f -name completed | wc -l | tr -d ' ')" = 2 ]

# Under critically low memory, do not launch another provider process. The run
# remains recoverable and exits with EX_TEMPFAIL-style status 75.
mkdir -p "$TMP/memory-counters" "$TMP/memory-state"
export FAKE_COUNTER_DIR="$TMP/memory-counters"
export FAKE_SLEEP_CODE=0
export DEEP_REVIEW_STATE_DIR="$TMP/memory-state"
export DEEP_REVIEW_AVAILABLE_MEMORY_MB_OVERRIDE=100
export DEEP_REVIEW_MIN_FREE_MB=768
set +e
bash "$TMP/skill/skills/deep-review/scripts/deep-review.sh" --provider codex --fresh code >"$TMP/memory.out" 2>"$TMP/memory.err"
memory_rc=$?
set -e
[ "$memory_rc" -eq 75 ]
[ ! -f "$TMP/memory-counters/code.count" ]
grep -q 'Review checkpoint saved:' "$TMP/memory.err"

# Accessibility remains part of every full review and keeps its explicit alias.
grep -q 'FULL=.*accessibility-scanner' "$RUNNER"
grep -q 'a11y) echo accessibility-scanner' "$RUNNER"

echo "runner resilience test passed"
