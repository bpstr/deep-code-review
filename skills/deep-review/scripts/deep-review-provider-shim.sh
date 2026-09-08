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

checkpoint=""
marker=""
rel=""
if [ -n "$target" ]; then
  rel="${target#"$work_dir"/}"
  checkpoint="$run_dir/checkpoints/data/$rel"
  marker="$run_dir/checkpoints/complete/$rel"
fi

batch_checkpoint_valid() {
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
  printf 'Recovered completed stage: %s\n' "$rel" >&2
  exit 0
fi

invalidate_file() {
  stale_rel="$1"
  rm -f "$run_dir/checkpoints/data/$stale_rel" \
        "$run_dir/checkpoints/complete/$stale_rel" \
        "$work_dir/$stale_rel" 2>/dev/null || true
}
invalidate_tree() {
  stale_rel="$1"
  rm -rf "$run_dir/checkpoints/data/$stale_rel" \
         "$run_dir/checkpoints/complete/$stale_rel" \
         "$work_dir/$stale_rel" 2>/dev/null || true
}
invalidate_downstream() {
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

slot_owned=""
slot_claim=""
acquire_global_slot() {
  slot_root="${DEEP_REVIEW_GLOBAL_SLOT_DIR:?}"
  slot_max="${DEEP_REVIEW_GLOBAL_SLOT_MAX:-1}"
  mkdir -p "$slot_root"
  slot_claim="$slot_root/.claim.$$"
  printf '%s\n%s\n' "$$" "${DEEP_REVIEW_BOOT_ID:-unknown}" >"$slot_claim"
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
      if [ -s "$slot" ]; then
        slot_pid="$(sed -n '1p' "$slot" 2>/dev/null || true)"
        slot_boot="$(sed -n '2p' "$slot" 2>/dev/null || true)"
        stale=0
        [ "$slot_boot" = "${DEEP_REVIEW_BOOT_ID:-unknown}" ] || stale=1
        case "$slot_pid" in *[!0-9]*|'') stale=1;; esac
        if [ "$stale" -eq 0 ] && ! kill -0 "$slot_pid" 2>/dev/null; then stale=1; fi
        if [ "$stale" -eq 1 ]; then
          rm -f "$slot" 2>/dev/null || true
          continue
        fi
      else
        rm -f "$slot" 2>/dev/null || true
        continue
      fi
      i=$((i + 1))
    done
    sleep 0.2
  done
}
release_global_slot() {
  [ -z "$slot_owned" ] || rm -f "$slot_owned" 2>/dev/null || true
  [ -z "$slot_claim" ] || rm -f "$slot_claim" 2>/dev/null || true
  slot_owned=""
  slot_claim=""
}

provider_pid=""
forward_provider_signal() {
  signal="$1"
  if [ -n "$provider_pid" ]; then
    kill -"$signal" "$provider_pid" 2>/dev/null || true
  else
    release_global_slot
    exit 143
  fi
}
trap 'forward_provider_signal TERM' TERM
trap 'forward_provider_signal INT' INT
trap 'forward_provider_signal HUP' HUP

acquire_global_slot
"$real" "$@" &
provider_pid=$!
wait "$provider_pid"
status=$?
provider_pid=""
release_global_slot
trap - TERM INT HUP

checkpoint_file_atomic() {
  source_file="$1"
  destination="$2"
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
  [ "$complete" -eq 1 ] || exit 1

  for n in $batch_findings; do
    score_file="$work_dir/findings/score-$n.txt"
    checkpoint_file_atomic "$score_file" "$run_dir/checkpoints/data/findings/score-$n.txt" || exit 1
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
      [ "$complete" -eq 1 ] || exit "$status"
      n=1
      while [ "$n" -le "$count" ]; do
        finding="$work_dir/findings/finding-$n.md"
        checkpoint_file_atomic "$finding" "$run_dir/checkpoints/data/findings/finding-$n.md" || exit 1
        n=$((n + 1))
      done
    fi
  fi
  mkdir -p "$(dirname "$checkpoint")" "$(dirname "$marker")"
  checkpoint_file_atomic "$target" "$checkpoint" || exit 1
  marker_tmp="$marker.tmp.$$"
  printf 'complete\n' >"$marker_tmp"
  mv "$marker_tmp" "$marker"
fi
exit "$status"
