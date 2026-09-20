#!/usr/bin/env bash
# Sourced by the engine. Only runner-owned checkpoint/artifact paths are touched.
# Supplement the wrapper's source/scope fingerprint with prompt/evidence identity.
refresh_review_cache() {
  local signature file stamp force_refresh
  [ -n "${DEEP_REVIEW_PERSISTENT_RUN_DIR:-}" ] || return 0
  stamp="$DEEP_REVIEW_PERSISTENT_RUN_DIR/checkpoints/input-signature"
  force_refresh="${ARCH_TOOLS:-0}"
  signature="$(
    {
      cksum "$SCRIPT_DIR/deep-review-engine.sh" "$SCRIPT_DIR/review-cache.sh"
      cksum "$SKILL_DIR/support/architecture-review.md" "$SKILL_DIR/support/architecture-context.md"
      cksum "$SKILL_DIR/support/finding-validation.md" "$SCRIPT_DIR/architecture-evidence.py"
      cksum "$STACK_PROFILER" "$AGENT_DIR/synthesizer.md"
      cksum <"$ARCH_EVIDENCE_FILE"
      for file in $AGENTS; do cksum "$AGENT_DIR/$file.md"; done
    } | cksum | awk '{print $1 "-" $2}'
  )"
  if [ "$force_refresh" -eq 1 ] || [ ! -s "$stamp" ] || [ "$(cat "$stamp")" != "$signature" ]; then
    rm -rf "$DEEP_REVIEW_PERSISTENT_RUN_DIR/checkpoints/data" "$DEEP_REVIEW_PERSISTENT_RUN_DIR/checkpoints/complete"
    mkdir -p "$DEEP_REVIEW_PERSISTENT_RUN_DIR/checkpoints/data" "$DEEP_REVIEW_PERSISTENT_RUN_DIR/checkpoints/complete"
    rm -f "$REVIEW_DIR/stack-context.md" "$REVIEW_DIR/REPORT.md" "$REVIEW_DIR/FINAL.md"
    rm -rf "$REVIEW_DIR/findings"
    for file in $AGENTS; do rm -f "$REVIEW_DIR/$file.md"; done
    printf '%s\n' "$signature" >"$stamp"
    echo 'Review checkpoints refreshed for current prompts/evidence.' >&2
  fi
}
