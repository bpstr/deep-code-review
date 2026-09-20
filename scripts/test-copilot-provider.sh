#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNNER="$ROOT/skills/deep-review/scripts/deep-review.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/deep-review-copilot-test.XXXXXX")"
cleanup() {
  jobs -pr 2>/dev/null | xargs kill -TERM 2>/dev/null || true
  rm -rf "$TMP"
}
trap cleanup EXIT INT TERM

mkdir -p "$TMP/repo with spaces" "$TMP/bin" "$TMP/temp artifacts"
cd "$TMP/repo with spaces"
git init -q -b main 2>/dev/null || { git init -q; git checkout -qb main; }
git config user.email test@example.com
git config user.name "Deep Review Copilot Test"
printf 'base\n' >target.py
git add target.py
git commit -qm init
git checkout -qb feature
printf 'changed\n' >target.py
git commit -qam feature

cat >"$TMP/bin/copilot" <<'EOF_COPILOT'
#!/usr/bin/env bash
set -euo pipefail

fail() { echo "Fake Copilot: $*" >&2; exit 90; }
prompt=""
model=""
allowed=""
available=""
silent=0
no_ask=0
no_instructions=0
no_mcps=0
no_updates=0
no_color=0
no_bash_env=0
skill_dir=0
artifact_dir=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    -p) prompt="$2"; shift 2 ;;
    -s) silent=1; shift ;;
    --no-ask-user) no_ask=1; shift ;;
    --no-custom-instructions) no_instructions=1; shift ;;
    --disable-builtin-mcps) no_mcps=1; shift ;;
    --no-auto-update) no_updates=1; shift ;;
    --no-color) no_color=1; shift ;;
    --no-bash-env) no_bash_env=1; shift ;;
    --model) model="$2"; shift 2 ;;
    --allow-tool) allowed="${allowed:+$allowed,}$2"; shift 2 ;;
    --available-tools)
      shift
      while [ "$#" -gt 0 ]; do
        case "$1" in --*) break ;; esac
        available="${available:+$available,}$1"
        shift
      done
      ;;
    --add-dir)
      if [ "$2" = "${FAKE_SKILL_DIR:?}" ]; then skill_dir=1
      elif [ "$2" = "${DEEP_REVIEW_ACTIVE_WORK_DIR:?}" ]; then artifact_dir=1
      else fail "unexpected additional directory"
      fi
      shift 2
      ;;
    *) fail "unexpected option: $1" ;;
  esac
done
[ -n "$prompt" ] || fail "missing -p prompt"
[ "$silent$no_ask$no_instructions$no_mcps$no_updates$no_color$no_bash_env" = 1111111 ] || fail "missing automation controls"
[ "$skill_dir$artifact_dir" = 11 ] || fail "missing outside-repository path grants"
[ "$available" = 'view,grep,glob,create,edit,apply_patch,bash' ] || fail "unexpected available tools"
[ "$allowed" = 'write,shell(git diff:*),shell(git show:*),shell(git log:*),shell(git blame:*),shell(git status:*),shell(git ls-files:*),shell(git rev-parse:*)' ] || fail "unexpected tool permissions"

work_dir="${DEEP_REVIEW_ACTIVE_WORK_DIR:?}"
run_dir="${DEEP_REVIEW_PERSISTENT_RUN_DIR:?}"
[ -x "$work_dir/.shims/copilot" ] || fail "provider shim not installed"
[ -n "${DEEP_REVIEW_REAL_COPILOT:-}" ] || fail "real provider not exported"
found_slot=0
for slot in "${DEEP_REVIEW_GLOBAL_SLOT_DIR:?}"/[0-9]*; do
  [ ! -f "$slot" ] || found_slot=1
done
[ "$found_slot" = 1 ] || fail "provider ran outside slot lifecycle"

stage=""
case "$prompt" in
  *"stack profiling instructions"*)
    stage=stack
    printf '# Shared stack context\nPython fixture.\n' >"$work_dir/stack-context.md"
    ;;
  *"specialized READ-ONLY code analysis agent"*)
    stage=reviewer
    target="$(printf '%s\n' "$prompt" | sed -n 's/^Write your complete Markdown findings to: //p' | head -1)"
    [ -n "$target" ] || fail "missing reviewer artifact target"
    printf '# Findings\n\nOne synthetic finding.\n' >"$target"
    ;;
  *"synthesis agent for a multi-agent code review"*)
    stage=synthesis
    printf '# Report\n\nOne synthetic finding.\n' >"$work_dir/REPORT.md"
    ;;
  *"extract every distinct code-review finding"*)
    stage=extract
    mkdir -p "$work_dir/findings"
    printf 'TITLE: Synthetic finding\nCLASSIFICATION: NEW\nSEVERITY: Important\nSOURCE: code-reviewer\nLOCATION: target.py:1\nDETAILS: synthetic fixture\n' >"$work_dir/findings/finding-1.md"
    printf '1\n' >"$work_dir/findings/count.txt"
    ;;
  *"confidence scorer for a batch"*)
    stage=score-batch
    printf 'SCORE: 95\nREASON: Synthetic confirmed fixture.\n' >"$work_dir/findings/score-1.txt"
    ;;
  *"final code-review triage editor"*)
    stage=final
    printf '# Copilot Final Review\n\nP1 synthetic finding\n' >"$work_dir/FINAL.md"
    ;;
  *) fail "unrecognized pipeline prompt" ;;
esac

if [ "${FAKE_EXPECT_MODELS:-0}" = 1 ]; then
  case "$stage" in
    stack|extract|score-batch) [ "$model" = "${FAKE_FAST_MODEL:?}" ] || fail "fast model not preserved" ;;
    *) [ "$model" = "${FAKE_REVIEW_MODEL:?}" ] || fail "review model not preserved" ;;
  esac
else
  [ -z "$model" ] || fail "runner forced a model when none was requested"
fi
printf '%s\n' "$stage" >>"${FAKE_CALL_LOG:?}"
EOF_COPILOT
chmod +x "$TMP/bin/copilot"

# A competing Codex binary makes explicit-provider selection and historical auto
# preference observable without ever calling a real model.
cat >"$TMP/bin/codex" <<'EOF_CODEX'
#!/usr/bin/env bash
printf 'codex\n' >>"${FAKE_AUTO_LOG:?}"
exit 88
EOF_CODEX
chmod +x "$TMP/bin/codex"

export PATH="$TMP/bin:$PATH"
export TMPDIR="$TMP/temp artifacts"
export DEEP_REVIEW_SLOT_DIR="$TMP/slots"
export FAKE_SKILL_DIR="$ROOT/skills/deep-review"
export FAKE_REVIEW_MODEL='review model with spaces'
export FAKE_FAST_MODEL='fast-model-beta'
export FAKE_AUTO_LOG="$TMP/auto-calls"

# Model-bearing argv after -p must not confuse shim stage/checkpoint detection.
FAKE_CALL_LOG="$TMP/calls" FAKE_EXPECT_MODELS=1 DEEP_REVIEW_STATE_DIR="$TMP/state" \
  bash "$RUNNER" --provider copilot --base main --max-concurrent 2 \
  --model "$FAKE_REVIEW_MODEL" --fast-model "$FAKE_FAST_MODEL" \
  --output "$TMP/final.md" code python >"$TMP/stdout" 2>"$TMP/stderr"
grep -q '^# Copilot Final Review' "$TMP/stdout"
cmp "$TMP/stdout" "$TMP/final.md"
[ "$(grep -c '^reviewer$' "$TMP/calls")" -eq 2 ]
for stage in stack synthesis extract score-batch final; do
  [ "$(grep -c "^$stage$" "$TMP/calls")" -eq 1 ]
done
[ ! -e "$FAKE_AUTO_LOG" ]

artifacts="$(DEEP_REVIEW_STATE_DIR="$TMP/state" bash "$RUNNER" --latest-artifacts)"
for stage in stack reviewer synthesis extract score-batch final; do
  matched=0
  for state in "$artifacts/lifecycle"/*.state; do
    if grep -q "^stage=$stage$" "$state"; then
      grep -q '^provider=copilot$' "$state"
      grep -q '^state=completed$' "$state"
      matched=1
    fi
  done
  [ "$matched" = 1 ]
done
test -s "$artifacts/../checkpoints/complete/findings/score-batch-1.complete"
git diff --exit-code
[ -z "$(git status --porcelain)" ]

# Environment selection and omitted models follow the same pipeline.
FAKE_CALL_LOG="$TMP/default-calls" DEEP_REVIEW_PROVIDER=copilot DEEP_REVIEW_STATE_DIR="$TMP/default-state" \
  bash "$RUNNER" --max-concurrent 1 code >"$TMP/default.out" 2>"$TMP/default.err"
grep -q '^# Copilot Final Review' "$TMP/default.out"
[ "$(wc -l <"$TMP/default-calls" | tr -d ' ')" -eq 5 ]

# Installing Copilot must not silently change auto's Codex-then-Claude contract.
set +e
FAKE_CALL_LOG="$TMP/auto-copilot-calls" DEEP_REVIEW_PROVIDER=auto DEEP_REVIEW_STATE_DIR="$TMP/auto-state" \
  bash "$RUNNER" --max-concurrent 1 code >"$TMP/auto.out" 2>"$TMP/auto.err"
auto_status=$?
set -e
[ "$auto_status" -ne 0 ]
test -s "$FAKE_AUTO_LOG"
[ ! -e "$TMP/auto-copilot-calls" ]

DEEP_REVIEW_TEST_PROVIDER=copilot bash "$ROOT/scripts/test-provider-lifecycle.sh"
echo "Copilot provider orchestration and lifecycle tests passed"
