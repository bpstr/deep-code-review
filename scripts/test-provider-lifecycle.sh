#!/usr/bin/env bash
set -euo pipefail

CASE="${1:-all}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SHIM="$ROOT/skills/deep-review/scripts/deep-review-provider-shim.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/deep-review-provider-test.XXXXXX")"
cleanup() {
  jobs -pr 2>/dev/null | xargs kill -KILL 2>/dev/null || true
  rm -rf "$TMP"
}
trap cleanup EXIT INT TERM

mkdir -p "$TMP/bin" "$TMP/work" "$TMP/run/checkpoints/data" "$TMP/run/checkpoints/complete" "$TMP/slots"
cp "$SHIM" "$TMP/bin/provider-shim"
chmod +x "$TMP/bin/provider-shim"
ln -s provider-shim "$TMP/bin/codex"

cat >"$TMP/bin/fake-codex" <<'EOF_PROVIDER'
#!/usr/bin/env bash
set -u
printf '%s\n' "$$" >"${FAKE_PROVIDER_PID_FILE:?}"
: >"${FAKE_PROVIDER_STARTED:?}"
trap ':' TERM INT HUP
while :; do sleep 0.2; done
EOF_PROVIDER
chmod +x "$TMP/bin/fake-codex"

boot_id="test-boot"

fail_with_log() {
  message="$1"
  log_file="$2"
  echo "$message" >&2
  [ ! -f "$log_file" ] || cat "$log_file" >&2
  return 1
}

run_queue_test() {
  printf '%s\n%s\n' "$$" "$boot_id" >"$TMP/slots/1"
  set +e
  DEEP_REVIEW_REAL_CODEX="$TMP/bin/fake-codex" \
  DEEP_REVIEW_PERSISTENT_RUN_DIR="$TMP/run" \
  DEEP_REVIEW_ACTIVE_WORK_DIR="$TMP/work" \
  DEEP_REVIEW_GLOBAL_SLOT_DIR="$TMP/slots" \
  DEEP_REVIEW_GLOBAL_SLOT_MAX=1 \
  DEEP_REVIEW_BOOT_ID="$boot_id" \
  DEEP_REVIEW_SLOT_WAIT_TIMEOUT_SECONDS=1 \
  DEEP_REVIEW_SLOT_STATUS_INTERVAL_SECONDS=1 \
  FAKE_PROVIDER_PID_FILE="$TMP/provider-unused.pid" \
  FAKE_PROVIDER_STARTED="$TMP/provider-unused.started" \
    "$TMP/bin/codex" 'generic prompt' >"$TMP/queue.out" 2>"$TMP/queue.err"
  queue_status=$?
  set -e
  [ "$queue_status" -eq 75 ] || fail_with_log "queue test expected exit 75, got $queue_status" "$TMP/queue.err"
  grep -q '\[deep-review\] queued provider' "$TMP/queue.err" || fail_with_log "queue test missing queued state" "$TMP/queue.err"
  grep -q '\[deep-review\] timed_out provider' "$TMP/queue.err" || fail_with_log "queue test missing timed_out state" "$TMP/queue.err"
  grep -R -q '^state=timed_out$' "$TMP/work/lifecycle" || fail_with_log "queue test missing lifecycle artifact" "$TMP/queue.err"
  [ ! -e "$TMP/provider-unused.started" ] || fail_with_log "queue test unexpectedly started provider" "$TMP/queue.err"
  echo "queue lifecycle test passed"
}

run_cancel_test() {
  rm -f "$TMP/slots/1"
  rm -rf "$TMP/work/lifecycle"
  DEEP_REVIEW_REAL_CODEX="$TMP/bin/fake-codex" \
  DEEP_REVIEW_PERSISTENT_RUN_DIR="$TMP/run" \
  DEEP_REVIEW_ACTIVE_WORK_DIR="$TMP/work" \
  DEEP_REVIEW_GLOBAL_SLOT_DIR="$TMP/slots" \
  DEEP_REVIEW_GLOBAL_SLOT_MAX=1 \
  DEEP_REVIEW_BOOT_ID="$boot_id" \
  DEEP_REVIEW_SLOT_WAIT_TIMEOUT_SECONDS=5 \
  DEEP_REVIEW_PROVIDER_TIMEOUT_SECONDS=30 \
  DEEP_REVIEW_PROVIDER_TERMINATION_GRACE_SECONDS=1 \
  FAKE_PROVIDER_PID_FILE="$TMP/provider.pid" \
  FAKE_PROVIDER_STARTED="$TMP/provider.started" \
    "$TMP/bin/codex" 'generic prompt' >"$TMP/cancel.out" 2>"$TMP/cancel.err" &
  shim_pid=$!

  n=0
  while [ ! -e "$TMP/provider.started" ] && [ "$n" -lt 100 ]; do sleep 0.05; n=$((n + 1)); done
  [ -e "$TMP/provider.started" ] || fail_with_log "cancel test provider did not start" "$TMP/cancel.err"
  provider_pid="$(cat "$TMP/provider.pid")"
  kill -0 "$provider_pid" || fail_with_log "cancel test provider not alive before cancellation" "$TMP/cancel.err"
  [ -e "$TMP/slots/1" ] || fail_with_log "cancel test provider slot missing before cancellation" "$TMP/cancel.err"
  kill -TERM "$shim_pid"
  set +e
  wait "$shim_pid"
  cancel_status=$?
  set -e
  [ "$cancel_status" -eq 143 ] || fail_with_log "cancel test expected exit 143, got $cancel_status" "$TMP/cancel.err"
  ! kill -0 "$provider_pid" 2>/dev/null || fail_with_log "cancel test left provider alive" "$TMP/cancel.err"
  [ ! -e "$TMP/slots/1" ] || fail_with_log "cancel test left provider slot allocated" "$TMP/cancel.err"
  grep -q 'sending KILL' "$TMP/cancel.err" || fail_with_log "cancel test did not escalate to KILL" "$TMP/cancel.err"
  grep -R -q '^state=cancelled$' "$TMP/work/lifecycle" || fail_with_log "cancel test missing cancelled state" "$TMP/cancel.err"
  echo "cancellation lifecycle test passed"
}

run_timeout_test() {
  rm -f "$TMP/slots/1" "$TMP/provider.started" "$TMP/provider.pid"
  rm -rf "$TMP/work/lifecycle"
  DEEP_REVIEW_REAL_CODEX="$TMP/bin/fake-codex" \
  DEEP_REVIEW_PERSISTENT_RUN_DIR="$TMP/run" \
  DEEP_REVIEW_ACTIVE_WORK_DIR="$TMP/work" \
  DEEP_REVIEW_GLOBAL_SLOT_DIR="$TMP/slots" \
  DEEP_REVIEW_GLOBAL_SLOT_MAX=1 \
  DEEP_REVIEW_BOOT_ID="$boot_id" \
  DEEP_REVIEW_SLOT_WAIT_TIMEOUT_SECONDS=5 \
  DEEP_REVIEW_PROVIDER_TIMEOUT_SECONDS=1 \
  DEEP_REVIEW_PROVIDER_TERMINATION_GRACE_SECONDS=1 \
  FAKE_PROVIDER_PID_FILE="$TMP/provider.pid" \
  FAKE_PROVIDER_STARTED="$TMP/provider.started" \
    "$TMP/bin/codex" 'generic prompt' >"$TMP/timeout.out" 2>"$TMP/timeout.err" &
  timeout_shim_pid=$!
  set +e
  wait "$timeout_shim_pid"
  timeout_status=$?
  set -e
  [ "$timeout_status" -eq 124 ] || fail_with_log "timeout test expected exit 124, got $timeout_status" "$TMP/timeout.err"
  timeout_provider_pid="$(cat "$TMP/provider.pid")"
  ! kill -0 "$timeout_provider_pid" 2>/dev/null || fail_with_log "timeout test left provider alive" "$TMP/timeout.err"
  [ ! -e "$TMP/slots/1" ] || fail_with_log "timeout test left provider slot allocated" "$TMP/timeout.err"
  grep -q 'provider exceeded 1s' "$TMP/timeout.err" || fail_with_log "timeout test missing timeout diagnostic" "$TMP/timeout.err"
  grep -R -q '^state=timed_out$' "$TMP/work/lifecycle" || fail_with_log "timeout test missing timed_out state" "$TMP/timeout.err"
  echo "execution-timeout lifecycle test passed"
}

case "$CASE" in
  queue) run_queue_test ;;
  cancel) run_cancel_test ;;
  timeout) run_timeout_test ;;
  all)
    run_queue_test
    run_cancel_test
    run_timeout_test
    ;;
  *) echo "Unknown lifecycle test case: $CASE" >&2; exit 2 ;;
esac
