#!/usr/bin/env bash
set -e
for arg in "$@"; do
  case "$arg" in
    *deep-review.XXXXXX*)
      mkdir -p "$DEEP_REVIEW_ACTIVE_WORK_DIR"
      printf '%s\n' "$DEEP_REVIEW_ACTIVE_WORK_DIR"
      exit 0
      ;;
  esac
done
exec "$DEEP_REVIEW_REAL_MKTEMP" "$@"
