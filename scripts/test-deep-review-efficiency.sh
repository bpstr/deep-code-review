#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNNER="$ROOT/skills/deep-review/scripts/deep-review.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/deep-review-efficiency-test.XXXXXX")"
cleanup() {
  jobs -pr 2>/dev/null | xargs kill -TERM 2>/dev/null || true
  rm -rf "$TMP"
}
trap cleanup EXIT INT TERM

mkdir -p "$TMP/repo" "$TMP/bin"
cd "$TMP/repo"
git init -q -b main 2>/dev/null || { git init -q; git checkout -qb main; }
git config user.email test@example.com
git config user.name "Deep Review Efficiency Test"
printf 'base\n' > target.txt
git add target.txt
git commit -qm init
git checkout -qb feature
printf 'changed\n' > target.txt
git commit -qam feature

cat >"$TMP/bin/codex" <<'EOF_CODEX'
#!/usr/bin/env bash
set -u
prompt=""
for arg in "$@"; do prompt="$arg"; done
work_dir="${DEEP_REVIEW_ACTIVE_WORK_DIR:?}"

block_here() {
  : >"${FAKE_BLOCK_MARKER:?}"
  trap 'exit 143' TERM INT HUP
  while :; do sleep 0.2; done
}

if printf '%s' "$prompt" | grep -q 'specialized READ-ONLY code analysis agent'; then
  target="$(printf '%s\n' "$prompt" | sed -n 's/^Write your complete Markdown findings to: //p' | head -1)"
  echo reviewer >>"${FAKE_CALL_LOG:?}"
  if [ "${FAKE_SKIP_SILENT:-0}" = 1 ] && printf '%s' "$target" | grep -q 'silent-failure-hunter.md'; then exit 42; fi
  printf '# Findings\n\nSynthetic findings.\n' >"$target"
elif printf '%s' "$prompt" | grep -q 'synthesis agent for a multi-agent code review'; then
  echo synth >>"${FAKE_CALL_LOG:?}"
  printf '# Report\n\nFive findings.\n' >"$work_dir/REPORT.md"
elif printf '%s' "$prompt" | grep -q 'extract every distinct code-review finding'; then
  echo extract >>"${FAKE_CALL_LOG:?}"
  mkdir -p "$work_dir/findings"
  n=1
  while [ "$n" -le 5 ]; do
    printf 'TITLE: finding %s\nCLASSIFICATION: NEW\nSEVERITY: Important\nSOURCE: fake\nLOCATION: target.txt:1\nDETAILS: synthetic\n' "$n" >"$work_dir/findings/finding-$n.md"
    n=$((n + 1))
  done
  echo 5 >"$work_dir/findings/count.txt"
elif printf '%s' "$prompt" | grep -q 'confidence scorer for a batch'; then
  ids="$(printf '%s\n' "$prompt" | sed -n 's/^Batch findings:[[:space:]]*//p' | head -1)"
  if [ "${FAKE_ASSERT_SINGLE_DIFF:-0}" = 1 ]; then
    [ "$(grep -c '^diff --git a/target.txt b/target.txt' "$work_dir/review.diff" 2>/dev/null || true)" -eq 1 ] || exit 43
  fi
  printf 'batch:%s\n' "$ids" >>"${FAKE_CALL_LOG:?}"
  if [ "${FAKE_BLOCK_LAST_BATCH:-0}" = 1 ] && printf '%s\n' "$ids" | grep -Eq '(^|[[:space:]])5($|[[:space:]])'; then
    block_here
  fi
  for n in $ids; do
    printf 'SCORE: 95\nREASON: synthetic confirmation\n' >"$work_dir/findings/score-$n.txt"
  done
elif printf '%s' "$prompt" | grep -q 'final code-review triage editor'; then
  echo final >>"${FAKE_CALL_LOG:?}"
  printf '# Final Review\n\nP1 synthetic finding\n' >"$work_dir/FINAL.md"
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

# Five findings should use two confidence provider calls at the default batch size of 4,
# while the final report remains both stdout-visible and durably exported.
STATE="$TMP/state"
CALLS="$TMP/calls"
GITHUB_OUT="$TMP/github-output"
: >"$CALLS"
: >"$GITHUB_OUT"
PATH="$TMP/bin:$PATH" FAKE_CALL_LOG="$CALLS" DEEP_REVIEW_PROVIDER=codex DEEP_REVIEW_STATE_DIR="$STATE" GITHUB_OUTPUT="$GITHUB_OUT" \
  bash "$RUNNER" --max-concurrent 2 --results-dir "$TMP/results" --output "$TMP/final.md" code >"$TMP/stdout" 2>"$TMP/stderr"
[ "$(grep -c '^batch:' "$CALLS")" -eq 2 ]
grep -q '^# Final Review' "$TMP/stdout"
grep -q 'P1 synthetic finding' "$TMP/final.md"
grep -q 'P1 synthetic finding' "$TMP/results/latest.md"
grep -q '^deep_review_result=' "$GITHUB_OUT"
latest="$(PATH="$TMP/bin:$PATH" DEEP_REVIEW_PROVIDER=codex DEEP_REVIEW_STATE_DIR="$STATE" bash "$RUNNER" --latest-result)"
[ -s "$latest" ]
cmp "$TMP/stdout" "$latest"

# Review-gap annotations are part of the canonical result as well as stdout.
STATE_GAP="$TMP/state-gap"
CALLS_GAP="$TMP/calls-gap"
: >"$CALLS_GAP"
PATH="$TMP/bin:$PATH" FAKE_CALL_LOG="$CALLS_GAP" FAKE_SKIP_SILENT=1 DEEP_REVIEW_PROVIDER=codex DEEP_REVIEW_STATE_DIR="$STATE_GAP" \
  bash "$RUNNER" --max-concurrent 2 code errors >"$TMP/gap.out" 2>"$TMP/gap.err"
gap_result="$(PATH="$TMP/bin:$PATH" DEEP_REVIEW_PROVIDER=codex DEEP_REVIEW_STATE_DIR="$STATE_GAP" bash "$RUNNER" --latest-result)"
grep -q 'Review gaps: silent-failure-hunter' "$TMP/gap.out"
cmp "$TMP/gap.out" "$gap_result"

# A completed batch is a recovery unit. Interrupt the second batch, then verify resume
# reuses the first four scores instead of launching their provider call again.
STATE_REC="$TMP/state-recovery"
CALLS_REC="$TMP/calls-recovery"
BLOCK_REC="$TMP/block-recovery"
: >"$CALLS_REC"
PATH="$TMP/bin:$PATH" FAKE_CALL_LOG="$CALLS_REC" FAKE_BLOCK_LAST_BATCH=1 FAKE_BLOCK_MARKER="$BLOCK_REC" \
  DEEP_REVIEW_PROVIDER=codex DEEP_REVIEW_STATE_DIR="$STATE_REC" DEEP_REVIEW_SCORE_BATCH_SIZE=4 \
  bash "$RUNNER" --max-concurrent 1 code >"$TMP/rec-first.out" 2>"$TMP/rec-first.err" &
rec_pid=$!
wait_for_file "$BLOCK_REC"
kill -TERM "$rec_pid"
set +e
wait "$rec_pid"
set -e
[ "$(grep -c '^batch:1 2 3 4$' "$CALLS_REC")" -eq 1 ]
[ "$(grep -c '^batch:5$' "$CALLS_REC")" -eq 1 ]

PATH="$TMP/bin:$PATH" FAKE_CALL_LOG="$CALLS_REC" DEEP_REVIEW_PROVIDER=codex DEEP_REVIEW_STATE_DIR="$STATE_REC" DEEP_REVIEW_SCORE_BATCH_SIZE=4 \
  bash "$RUNNER" --max-concurrent 1 code >"$TMP/rec-second.out" 2>"$TMP/rec-second.err"
grep -q 'Resuming interrupted review run:' "$TMP/rec-second.err"
[ "$(grep -c '^batch:1 2 3 4$' "$CALLS_REC")" -eq 1 ]
[ "$(grep -c '^batch:5$' "$CALLS_REC")" -eq 2 ]


# --changes reads staged + unstaged tracked data once. A staged file should appear only
# once in the scorer diff rather than once from HEAD and again from --cached.
STATE_CHANGES="$TMP/state-changes"
CALLS_CHANGES="$TMP/calls-changes"
: >"$CALLS_CHANGES"
printf 'staged-change\n' > target.txt
git add target.txt
PATH="$TMP/bin:$PATH" FAKE_CALL_LOG="$CALLS_CHANGES" FAKE_ASSERT_SINGLE_DIFF=1 DEEP_REVIEW_PROVIDER=codex DEEP_REVIEW_STATE_DIR="$STATE_CHANGES" \
  bash "$RUNNER" --no-resume --changes code >"$TMP/changes.out" 2>"$TMP/changes.err"
git reset -q HEAD -- target.txt
git checkout -q -- target.txt

# Branch-review fingerprints ignore unrelated dirty/untracked working-tree bytes because
# that scope reviews committed HEAD. This prevents expensive whole-worktree hashing.
STATE_FP="$TMP/state-fingerprint"
CALLS_FP="$TMP/calls-fingerprint"
: >"$CALLS_FP"
printf 'unrelated-a\n' > unrelated.tmp
PATH="$TMP/bin:$PATH" FAKE_CALL_LOG="$CALLS_FP" DEEP_REVIEW_PROVIDER=codex DEEP_REVIEW_STATE_DIR="$STATE_FP" \
  bash "$RUNNER" --no-resume code >"$TMP/fp-a.out" 2>"$TMP/fp-a.err"
printf 'unrelated-b\n' > unrelated.tmp
PATH="$TMP/bin:$PATH" FAKE_CALL_LOG="$CALLS_FP" DEEP_REVIEW_PROVIDER=codex DEEP_REVIEW_STATE_DIR="$STATE_FP" \
  bash "$RUNNER" --no-resume code >"$TMP/fp-b.out" 2>"$TMP/fp-b.err"
[ "$(find "$STATE_FP" -name fingerprint -type f -exec cat {} \; | sort -u | wc -l | tr -d ' ')" -eq 1 ]
rm -f unrelated.tmp

# Path reviews still fingerprint the requested path contents and therefore invalidate
# recovery identity when that path changes.
STATE_PATH="$TMP/state-path"
CALLS_PATH="$TMP/calls-path"
: >"$CALLS_PATH"
printf 'path-a\n' > loose.txt
PATH="$TMP/bin:$PATH" FAKE_CALL_LOG="$CALLS_PATH" DEEP_REVIEW_PROVIDER=codex DEEP_REVIEW_STATE_DIR="$STATE_PATH" \
  bash "$RUNNER" --no-resume loose.txt code >"$TMP/path-a.out" 2>"$TMP/path-a.err"
printf 'path-b\n' > loose.txt
PATH="$TMP/bin:$PATH" FAKE_CALL_LOG="$CALLS_PATH" DEEP_REVIEW_PROVIDER=codex DEEP_REVIEW_STATE_DIR="$STATE_PATH" \
  bash "$RUNNER" --no-resume loose.txt code >"$TMP/path-b.out" 2>"$TMP/path-b.err"
[ "$(find "$STATE_PATH" -name fingerprint -type f -exec cat {} \; | sort -u | wc -l | tr -d ' ')" -eq 2 ]
rm -f loose.txt

# CI/cloud defaults use a private job-local temp root when no explicit state directory is
# provided, avoiding assumptions that HOME is writable or persistent.
CALLS_CI="$TMP/calls-ci"
: >"$CALLS_CI"
PATH="$TMP/bin:$PATH" FAKE_CALL_LOG="$CALLS_CI" DEEP_REVIEW_PROVIDER=codex CI=1 RUNNER_TEMP="$TMP/runner-temp" HOME="$TMP/nonexistent-home" \
  bash "$RUNNER" code >"$TMP/ci.out" 2>"$TMP/ci.err"
find "$TMP/runner-temp" -path '*/artifacts/review.md' -type f | grep -q .

echo "deep-review efficiency/output smoke test passed"
