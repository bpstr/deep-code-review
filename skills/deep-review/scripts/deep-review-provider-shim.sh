#!/usr/bin/env bash
set -u
provider="$(basename "$0")"
case "$provider" in
  codex) real="${DEEP_REVIEW_REAL_CODEX:-}" ;;
  claude) real="${DEEP_REVIEW_REAL_CLAUDE:-}" ;;
  *) echo "Unknown provider shim: $provider" >&2; exit 127 ;;
esac
[ -n "$real" ] || { echo "Provider '$provider' is unavailable." >&2; exit 127; }

prompt=""
if [ "$provider" = codex ]; then
  for arg in "$@"; do prompt="$arg"; done
else
  want_prompt=0
  for arg in "$@"; do
    if [ "$want_prompt" -eq 1 ]; then prompt="$arg"; break; fi
    [ "$arg" != -p ] || want_prompt=1
  done
fi

run_dir="${DEEP_REVIEW_PERSISTENT_RUN_DIR:?}"
work_dir="${DEEP_REVIEW_ACTIVE_WORK_DIR:?}"
target=""
stage=""
batch_findings=""
case "$prompt" in
  *"specialized READ-ONLY code analysis agent"*)
    stage=reviewer
    target="$(printf '%s\n' "$prompt" | sed -n 's/^Write your complete Markdown findings to: //p' | head -1)"
    ;;
  *"stack profiling instructions"*) stage=stack; target="$work_dir/stack-context.md" ;;
  *"synthesis agent for a multi-agent code review"*) stage=synthesis; target="$work_dir/REPORT.md" ;;
  *"extract every distinct code-review finding"*) stage=extract; target="$work_dir/findings/count.txt" ;;
  *"independent code-review confidence scorer for a batch"*)
    stage=score-batch
    target="$(printf '%s\n' "$prompt" | sed -n 's/^Score batch marker: //p' | head -1)"
    batch_findings="$(printf '%s\n' "$prompt" | sed -n 's/^Batch findings:[[:space:]]*//p' | head -1)"
    ;;
  *"independent code-review confidence scorer"*)
    stage=score
    target="$(printf '%s\n' "$prompt" | sed -n 's/^Write exactly two lines to \(.*\):$/\1/p' | head -1)"
    ;;
  *"final code-review triage editor"*) stage=final; target="$work_dir/FINAL.md" ;;
esac
[ -n "$stage" ] || stage=provider

checkpoint=""
marker=""
rel=""
if [ -n "$target" ]; then
  rel="${target#"$work_dir"/}"
  checkpoint="$run_dir/checkpoints/data/$rel"
  marker="$run_dir/checkpoints/complete/$rel"
fi

lifecycle_dir="$work_dir/lifecycle"
mkdir -p "$lifecycle_dir"
label="$stage"
[ -z "$rel" ] || label="$stage:$rel"
lifecycle_key="$(printf '%s' "$label" | tr '/ :\t' '____' | tr -cd '[:alnum:]_.-')"
[ -n "$lifecycle_key" ] || lifecycle_key=provider
lifecycle_file="$lifecycle_dir/$lifecycle_key-$$.state"
write_state() {
  local state="$1"
  local detail="${2:-}"
  local state_now
  state_now="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date)"
  {
    printf 'state=%s\n' "$state"
    printf 'stage=%s\n' "$stage"
    printf 'label=%s\n' "$label"
    printf 'provider=%s\n' "$provider"
    printf 'shim_pid=%s\n' "$$"
    printf 'updated_at=%s\n' "$state_now"
    [ -z "$detail" ] || printf 'detail=%s\n' "$detail"
  } >"$lifecycle_file.tmp.$$"
  mv "$lifecycle_file.tmp.$$" "$lifecycle_file"
}
log_state() {
  local state="$1"
  local detail="${2:-}"
  if [ -n "$detail" ]; then
    printf '[deep-review] %s %s (%s)\n' "$state" "$label" "$detail" >&2
  else
    printf '[deep-review] %s %s\n' "$state" "$label" >&2
  fi
}

batch_checkpoint_valid() {
  local n
  [ "$stage" = score-batch ] || return 0
  [ -n "$batch_findings" ] || return 1
  for n in $batch_findings; do
    [ -s "$run_dir/checkpoints/data/findings/score-$n.txt" ] || return 1
  done
  return 0
}

if [ -n "$target" ] && [ -s "$checkpoint" ] && [ -f "$marker" ] && batch_checkpoint_valid; then
  mkdir -p "$(dirname "$target")"
  cp "$checkpoint" "$target"
  if [ "$stage" = score-batch ]; then
    for n in $batch_findings; do
      cp "$run_dir/checkpoints/data/findings/score-$n.txt" "$work_dir/findings/score-$n.txt"
    done
  fi
  write_state recovered "checkpoint=$rel"
  printf 'Recovered completed stage: %s\n' "$rel" >&2
  exit 0
fi

invalidate_file() {
  local stale_rel="$1"
  rm -f "$run_dir/checkpoints/data/$stale_rel" \
        "$run_dir/checkpoints/complete/$stale_rel" \
        "$work_dir/$stale_rel" 2>/dev/null || true
}
invalidate_tree() {
  local stale_rel="$1"
  rm -rf "$run_dir/checkpoints/data/$stale_rel" \
         "$run_dir/checkpoints/complete/$stale_rel" \
         "$work_dir/$stale_rel" 2>/dev/null || true
}
invalidate_downstream() {
  local data_root old old_rel n
  case "$stage" in
    stack)
      data_root="$run_dir/checkpoints/data"
      if [ -d "$data_root" ]; then
        find "$data_root" -type f -print 2>/dev/null | while IFS= read -r old; do
          old_rel="${old#"$data_root"/}"
          rm -f "$work_dir/$old_rel" 2>/dev/null || true
        done
      fi
      rm -rf "$run_dir/checkpoints/data" "$run_dir/checkpoints/complete"
      mkdir -p "$run_dir/checkpoints/data" "$run_dir/checkpoints/complete"
      ;;
    reviewer)
      invalidate_file REPORT.md
      invalidate_tree findings
      invalidate_file FINAL.md
      ;;
    synthesis)
      invalidate_tree findings
      invalidate_file FINAL.md
      ;;
    extract)
      invalidate_tree findings
      mkdir -p "$work_dir/findings"
      invalidate_file FINAL.md
      ;;
    score)
      invalidate_file FINAL.md
      ;;
    score-batch)
      for n in $batch_findings; do invalidate_file "findings/score-$n.txt"; done
      invalidate_file FINAL.md
      ;;
  esac
}

if [ -n "$target" ]; then
  invalidate_downstream
  rm -f "$marker" "$checkpoint" "$target" 2>/dev/null || true
fi

positive_integer() {
  local value="$1"
  case "$value" in *[!0-9]*|'') return 1;; esac
  [ "$value" -gt 0 ]
}
SLOT_WAIT_TIMEOUT="${DEEP_REVIEW_SLOT_WAIT_TIMEOUT_SECONDS:-120}"
SLOT_STATUS_INTERVAL="${DEEP_REVIEW_SLOT_STATUS_INTERVAL_SECONDS:-5}"
PROVIDER_TIMEOUT="${DEEP_REVIEW_PROVIDER_TIMEOUT_SECONDS:-1800}"
TERMINATION_GRACE="${DEEP_REVIEW_PROVIDER_TERMINATION_GRACE_SECONDS:-10}"
positive_integer "$SLOT_WAIT_TIMEOUT" || { echo "DEEP_REVIEW_SLOT_WAIT_TIMEOUT_SECONDS must be positive." >&2; exit 2; }
positive_integer "$SLOT_STATUS_INTERVAL" || { echo "DEEP_REVIEW_SLOT_STATUS_INTERVAL_SECONDS must be positive." >&2; exit 2; }
positive_integer "$PROVIDER_TIMEOUT" || { echo "DEEP_REVIEW_PROVIDER_TIMEOUT_SECONDS must be positive." >&2; exit 2; }
positive_integer "$TERMINATION_GRACE" || { echo "DEEP_REVIEW_PROVIDER_TERMINATION_GRACE_SECONDS must be positive." >&2; exit 2; }

process_identity() {
  local pid="$1"
  case "$pid" in *[!0-9]*|'') return 1;; esac
  if [ -r "/proc/$pid/stat" ]; then
    awk '{print $22}' "/proc/$pid/stat" 2>/dev/null && return 0
  fi
  if command -v ps >/dev/null 2>&1; then
    ps -o lstart= -p "$pid" 2>/dev/null | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | grep . && return 0
  fi
  return 1
}

slot_owned=""
slot_claim=""
release_global_slot() {
  [ -z "$slot_owned" ] || rm -f "$slot_owned" 2>/dev/null || true
  [ -z "$slot_claim" ] || rm -f "$slot_claim" 2>/dev/null || true
  slot_owned=""
  slot_claim=""
}
slot_is_stale() {
  local slot="$1"
  local slot_pid slot_boot slot_identity current_identity
  [ -s "$slot" ] || return 0
  slot_pid="$(sed -n '1p' "$slot" 2>/dev/null || true)"
  slot_boot="$(sed -n '2p' "$slot" 2>/dev/null || true)"
  slot_identity="$(sed -n '3p' "$slot" 2>/dev/null || true)"
  [ "$slot_boot" = "${DEEP_REVIEW_BOOT_ID:-unknown}" ] || return 0
  case "$slot_pid" in *[!0-9]*|'') return 0;; esac
  kill -0 "$slot_pid" 2>/dev/null || return 0
  current_identity="$(process_identity "$slot_pid" 2>/dev/null || true)"
  if [ -n "$slot_identity" ] && [ -n "$current_identity" ] && [ "$slot_identity" != "$current_identity" ]; then
    return 0
  fi
  return 1
}
acquire_global_slot() {
  local slot_root="${DEEP_REVIEW_GLOBAL_SLOT_DIR:?}"
  local slot_max="${DEEP_REVIEW_GLOBAL_SLOT_MAX:-1}"
  local self_identity started next_status i slot loop_now elapsed
  mkdir -p "$slot_root"
  self_identity="$(process_identity "$$" 2>/dev/null || true)"
  slot_claim="$slot_root/.claim.$$"
  printf '%s\n%s\n%s\n' "$$" "${DEEP_REVIEW_BOOT_ID:-unknown}" "$self_identity" >"$slot_claim"
  started="$(date +%s)"
  next_status="$started"
  write_state queued "slots=$slot_max timeout=${SLOT_WAIT_TIMEOUT}s"
  log_state queued "waiting for provider slot; timeout=${SLOT_WAIT_TIMEOUT}s"
  while :; do
    i=1
    while [ "$i" -le "$slot_max" ]; do
      slot="$slot_root/$i"
      if ln "$slot_claim" "$slot" 2>/dev/null; then
        rm -f "$slot_claim"
        slot_claim=""
        slot_owned="$slot"
        return 0
      fi
      if slot_is_stale "$slot"; then
        rm -f "$slot" 2>/dev/null || true
        continue
      fi
      i=$((i + 1))
    done
    loop_now="$(date +%s)"
    elapsed=$((loop_now - started))
    if [ "$elapsed" -ge "$SLOT_WAIT_TIMEOUT" ]; then
      write_state timed_out "phase=queue waited=${elapsed}s slots=$slot_max"
      log_state timed_out "provider slot unavailable after ${elapsed}s"
      release_global_slot
      return 75
    fi
    if [ "$loop_now" -ge "$next_status" ]; then
      next_status=$((loop_now + SLOT_STATUS_INTERVAL))
      write_state queued "waited=${elapsed}s slots=$slot_max"
      [ "$elapsed" -eq 0 ] || log_state queued "waited=${elapsed}s; slots=$slot_max"
    fi
    sleep 0.2
  done
}

signal_process_tree() {
  local signal="$1"
  local root_pid="$2"
  local children child
  children="$(ps -eo pid=,ppid= 2>/dev/null | awk -v parent="$root_pid" '$2 == parent { print $1 }')"
  for child in $children; do
    signal_process_tree "$signal" "$child"
  done
  kill -"$signal" "$root_pid" 2>/dev/null || true
}

provider_pid=""
watchdog_pid=""
shutdown_requested=0
shutdown_signal=""
timed_out=0
forward_provider_signal() {
  local signal="$1"
  shutdown_requested=1
  shutdown_signal="$signal"
  if [ -n "$provider_pid" ]; then
    signal_process_tree "$signal" "$provider_pid"
  else
    write_state cancelled "phase=queue signal=$signal"
    release_global_slot
    exit 143
  fi
}
timeout_provider() {
  timed_out=1
  shutdown_requested=1
  shutdown_signal=TERM
  write_state timed_out "phase=running timeout=${PROVIDER_TIMEOUT}s"
  log_state timed_out "provider exceeded ${PROVIDER_TIMEOUT}s; terminating"
  [ -z "$provider_pid" ] || signal_process_tree TERM "$provider_pid"
}
trap 'forward_provider_signal TERM' TERM
trap 'forward_provider_signal INT' INT
trap 'forward_provider_signal HUP' HUP
trap 'timeout_provider' USR1

acquire_global_slot
slot_status=$?
[ "$slot_status" -eq 0 ] || exit "$slot_status"
write_state running "slot=$(basename "$slot_owned") timeout=${PROVIDER_TIMEOUT}s"
log_state running "slot=$(basename "$slot_owned")"
provider_started="$(date +%s)"
"$real" "$@" &
provider_pid=$!
(
  sleep "$PROVIDER_TIMEOUT"
  kill -USR1 "$$" 2>/dev/null || true
) &
watchdog_pid=$!

status=0
while :; do
  wait "$provider_pid"
  status=$?
  if ! kill -0 "$provider_pid" 2>/dev/null; then
    break
  fi
  if [ "$shutdown_requested" -eq 1 ]; then
    grace_started="$(date +%s)"
    while kill -0 "$provider_pid" 2>/dev/null; do
      termination_now="$(date +%s)"
      if [ $((termination_now - grace_started)) -ge "$TERMINATION_GRACE" ]; then
        log_state terminating "provider ignored ${shutdown_signal:-TERM}; sending KILL"
        signal_process_tree KILL "$provider_pid"
        break
      fi
      sleep 0.2
    done
    wait "$provider_pid" 2>/dev/null || true
    if [ "$timed_out" -eq 1 ]; then status=124; else status=143; fi
    break
  fi
done
provider_pid=""
[ -z "$watchdog_pid" ] || kill "$watchdog_pid" 2>/dev/null || true
[ -z "$watchdog_pid" ] || wait "$watchdog_pid" 2>/dev/null || true
watchdog_pid=""
release_global_slot
trap - TERM INT HUP USR1
provider_finished="$(date +%s)"
runtime=$((provider_finished - provider_started))

checkpoint_file_atomic() {
  local source_file="$1"
  local destination="$2"
  local tmp
  mkdir -p "$(dirname "$destination")"
  tmp="$destination.tmp.$$"
  if ! cp "$source_file" "$tmp" || ! mv "$tmp" "$destination"; then
    rm -f "$tmp"
    return 1
  fi
}

if [ "$status" -eq 0 ] && [ "$stage" = score-batch ]; then
  complete=1
  [ -n "$batch_findings" ] || complete=0
  for n in $batch_findings; do
    score_file="$work_dir/findings/score-$n.txt"
    [ -s "$score_file" ] || complete=0
  done
  [ "$complete" -eq 1 ] || { write_state failed "runtime=${runtime}s incomplete-score-batch"; exit 1; }

  for n in $batch_findings; do
    score_file="$work_dir/findings/score-$n.txt"
    checkpoint_file_atomic "$score_file" "$run_dir/checkpoints/data/findings/score-$n.txt" || { write_state failed "runtime=${runtime}s checkpoint-write"; exit 1; }
  done
  printf 'complete\n' >"$target"
fi

if [ "$status" -eq 0 ] && [ -n "$target" ] && [ -s "$target" ]; then
  if [ "$target" = "$work_dir/findings/count.txt" ]; then
    count="$(tr -dc '0-9' <"$target" 2>/dev/null || true)"
    case "$count" in *[!0-9]*|'') count=-1;; esac
    if [ "$count" -ge 0 ] 2>/dev/null; then
      n=1
      complete=1
      while [ "$n" -le "$count" ]; do
        finding="$work_dir/findings/finding-$n.md"
        [ -s "$finding" ] || complete=0
        n=$((n + 1))
      done
      [ "$complete" -eq 1 ] || { write_state failed "runtime=${runtime}s incomplete-extraction"; exit 1; }
      n=1
      while [ "$n" -le "$count" ]; do
        finding="$work_dir/findings/finding-$n.md"
        checkpoint_file_atomic "$finding" "$run_dir/checkpoints/data/findings/finding-$n.md" || { write_state failed "runtime=${runtime}s checkpoint-write"; exit 1; }
        n=$((n + 1))
      done
    fi
  fi
  mkdir -p "$(dirname "$checkpoint")" "$(dirname "$marker")"
  checkpoint_file_atomic "$target" "$checkpoint" || { write_state failed "runtime=${runtime}s checkpoint-write"; exit 1; }
  marker_tmp="$marker.tmp.$$"
  printf 'complete\n' >"$marker_tmp"
  mv "$marker_tmp" "$marker"
fi

if [ "$status" -eq 0 ]; then
  write_state completed "runtime=${runtime}s"
  log_state completed "runtime=${runtime}s"
elif [ "$status" -eq 124 ] || [ "$timed_out" -eq 1 ]; then
  write_state timed_out "phase=running runtime=${runtime}s exit=$status"
elif [ "$status" -eq 143 ] && [ "$shutdown_requested" -eq 1 ]; then
  write_state cancelled "signal=${shutdown_signal:-TERM} runtime=${runtime}s"
else
  write_state failed "runtime=${runtime}s exit=$status"
  log_state failed "runtime=${runtime}s exit=$status"
fi
exit "$status"
