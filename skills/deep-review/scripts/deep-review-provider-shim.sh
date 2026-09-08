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
case "$prompt" in
  *"specialized READ-ONLY code analysis agent"*)
    target="$(printf '%s\n' "$prompt" | sed -n 's/^Write your complete Markdown findings to: //p' | head -1)"
    ;;
  *"stack profiling instructions"*) target="$work_dir/stack-context.md" ;;
  *"synthesis agent for a multi-agent code review"*) target="$work_dir/REPORT.md" ;;
  *"extract every distinct code-review finding"*) target="$work_dir/findings/count.txt" ;;
  *"independent code-review confidence scorer"*)
    target="$(printf '%s\n' "$prompt" | sed -n 's/^Write exactly two lines to \(.*\):$/\1/p' | head -1)"
    ;;
  *"final code-review triage editor"*) target="$work_dir/FINAL.md" ;;
esac

checkpoint=""
marker=""
if [ -n "$target" ]; then
  rel="${target#"$work_dir"/}"
  checkpoint="$run_dir/checkpoints/data/$rel"
  marker="$run_dir/checkpoints/complete/$rel"
fi
if [ -n "$target" ] && [ -s "$checkpoint" ] && [ -f "$marker" ]; then
  mkdir -p "$(dirname "$target")"
  cp "$checkpoint" "$target"
  printf 'Recovered completed stage: %s\n' "$rel" >&2
  exit 0
fi
[ -z "$marker" ] || rm -f "$marker"

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
      # A hard-link claim is atomic and the complete owner record exists before the slot
      # becomes visible. That avoids leaving an unrecoverable half-written mutex on crash.
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
        # Empty/malformed legacy slot files are never valid owners.
        rm -f "$slot" 2>/dev/null || true
        continue
      fi
      i=$((i + 1))
    done
    sleep 1
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
    # A shim may be waiting for a global memory slot before its provider exists.
    # Exit promptly so engine shutdown cannot leave a slot waiter orphaned.
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
if [ "$status" -eq 0 ] && [ -n "$target" ] && [ -s "$target" ]; then
  # Extractor completion is only durable when every declared finding exists.
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
      mkdir -p "$run_dir/checkpoints/data/findings"
      checkpoint_ok=1
      n=1
      while [ "$n" -le "$count" ]; do
        finding="$work_dir/findings/finding-$n.md"
        tmp="$run_dir/checkpoints/data/findings/finding-$n.md.tmp.$$"
        if ! cp "$finding" "$tmp" || ! mv "$tmp" "$run_dir/checkpoints/data/findings/finding-$n.md"; then
          rm -f "$tmp"
          checkpoint_ok=0
        fi
        n=$((n + 1))
      done
      [ "$checkpoint_ok" -eq 1 ] || exit 1
    fi
  fi
  mkdir -p "$(dirname "$checkpoint")" "$(dirname "$marker")"
  checkpoint_tmp="$checkpoint.tmp.$$"
  if ! cp "$target" "$checkpoint_tmp" || ! mv "$checkpoint_tmp" "$checkpoint"; then
    rm -f "$checkpoint_tmp"
    exit 1
  fi
  marker_tmp="$marker.tmp.$$"
  printf 'complete\n' >"$marker_tmp"
  mv "$marker_tmp" "$marker"
fi
exit "$status"
