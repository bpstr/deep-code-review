#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MANIFEST="$ROOT/reviewer-fixtures/architecture.tsv"
count=0
while IFS="$(printf '\t')" read -r name expectation pattern priority description; do
  [ "$name" != name ] || continue
  [ -n "$name" ] || continue
  test -d "$ROOT/reviewer-fixtures/$name"
  case "$expectation" in present|absent) ;; *) exit 1;; esac
  case "$priority" in -|P0|P1|P2) ;; *) exit 1;; esac
  [ -n "$pattern" ] && [ -n "$description" ]
  count=$((count + 1))
done <"$MANIFEST"
[ "$count" -ge 8 ]
echo "architecture fixture structure passed ($count fixtures)"
[ "${DEEP_REVIEW_RUN_LLM_FIXTURES:-0}" = 1 ] || {
  echo 'model-based architecture evaluation skipped (explicit opt-in required)'
  exit 0
}
TMP="$(mktemp -d "${TMPDIR:-/tmp}/architecture-fixtures.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
failed=0
while IFS="$(printf '\t')" read -r name expectation pattern priority description; do
  [ "$name" != name ] || continue
  [ -n "$name" ] || continue
  repo="$TMP/$name"
  mkdir -p "$repo"
  cp -R "$ROOT/reviewer-fixtures/$name/." "$repo/"
  args=(--provider "${DEEP_REVIEW_FIXTURE_PROVIDER:-auto}" --output "$TMP/$name-report.md")
  [ -z "${DEEP_REVIEW_FIXTURE_MODEL:-}" ] || args+=(--model "$DEEP_REVIEW_FIXTURE_MODEL")
  [ -z "${DEEP_REVIEW_FIXTURE_FAST_MODEL:-}" ] || args+=(--fast-model "$DEEP_REVIEW_FIXTURE_FAST_MODEL")
  if ! (
    cd "$repo"
    git init -q
    git add .
    git -c user.name=Fixture -c user.email=fixture@example.invalid commit -qm fixture
    CONFIDENCE_THRESHOLD=80 DEEP_REVIEW_AUTO_SPECIALISTS=0 \
      bash "$ROOT/scripts/deep-review.sh" "${args[@]}" . arch
  ) >"$TMP/$name.log" 2>&1; then
    echo "architecture fixture execution failed: $name" >&2
    failed=$((failed + 1))
    continue
  fi
  # Inspect only the final persisted report, never provider logs or echoed prompts.
  report="$TMP/$name-report.md"
  bad=0
  if [ "$expectation" = present ]; then
    grep -Eiq "$pattern" "$report" || bad=1
    [ "$priority" = - ] || grep -q "$priority" "$report" || bad=1
  else
    if grep -Eiq "$pattern" "$report"; then bad=1; fi
  fi
  if [ "$bad" -eq 1 ]; then
    echo "architecture calibration miss: $name — $description" >&2
    cat "$report" >&2
    failed=$((failed + 1))
  fi
done <"$MANIFEST"
[ "$failed" -eq 0 ] || { echo "$failed architecture calibration case(s) failed" >&2; exit 1; }
echo 'all model-based architecture fixtures passed'
