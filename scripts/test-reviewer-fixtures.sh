#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FIXTURES="$ROOT/reviewer-fixtures"
MANIFEST="$FIXTURES/manifest.tsv"
AGENTS="$ROOT/skills/deep-review/agents"

[ -s "$MANIFEST" ] || { echo "missing fixture manifest" >&2; exit 1; }

count=0
while IFS="$(printf '\t')" read -r name reviewer expectation pattern description; do
  [ -n "$name" ] || continue
  [ "$name" != "name" ] || continue
  count=$((count + 1))
  [ -d "$FIXTURES/$name" ] || { echo "missing fixture directory: $name" >&2; exit 1; }
  [ -s "$AGENTS/$reviewer.md" ] || { echo "unknown fixture reviewer: $reviewer" >&2; exit 1; }
  case "$expectation" in present|absent) ;; *) echo "invalid expectation for $name" >&2; exit 1;; esac
  [ -n "$pattern" ] || { echo "empty match pattern for $name" >&2; exit 1; }
done < "$MANIFEST"

[ "$count" -ge 8 ] || { echo "expected at least 8 calibration fixtures" >&2; exit 1; }

echo "reviewer fixture structure passed ($count fixtures)"

if [ "${DEEP_REVIEW_RUN_LLM_FIXTURES:-0}" != "1" ]; then
  echo "model-based fixture execution skipped; set DEEP_REVIEW_RUN_LLM_FIXTURES=1 to run it"
  exit 0
fi

provider="${DEEP_REVIEW_FIXTURE_PROVIDER:-auto}"
model="${DEEP_REVIEW_FIXTURE_MODEL:-}"
fast_model="${DEEP_REVIEW_FIXTURE_FAST_MODEL:-$model}"
failed=0

while IFS="$(printf '\t')" read -r name reviewer expectation pattern description; do
  [ -n "$name" ] || continue
  [ "$name" != "name" ] || continue

  tmp="$(mktemp -d "${TMPDIR:-/tmp}/deep-review-fixture.XXXXXX")"
  repo="$tmp/repo"
  mkdir -p "$repo"
  cp -R "$FIXTURES/$name/." "$repo/"

  (
    cd "$repo"
    git init -q
    git add .
    git -c user.name='Deep Review Fixture' -c user.email='fixture@example.invalid' commit -qm 'fixture'
  )

  output="$tmp/output.txt"
  args="--provider $provider"
  [ -z "$model" ] || args="$args --model $model"
  [ -z "$fast_model" ] || args="$args --fast-model $fast_model"

  echo "running fixture: $name ($reviewer)"
  if ! (
    cd "$repo"
    CONFIDENCE_THRESHOLD=0 DEEP_REVIEW_AUTO_SPECIALISTS=0 \
      bash "$ROOT/scripts/deep-review.sh" $args . "$reviewer"
  ) >"$output" 2>&1; then
    echo "fixture execution failed: $name" >&2
    cat "$output" >&2
    failed=$((failed + 1))
    rm -rf "$tmp"
    continue
  fi

  case "$expectation" in
    present)
      if ! grep -Eiq "$pattern" "$output"; then
        echo "fixture missed expected finding: $name — $description" >&2
        cat "$output" >&2
        failed=$((failed + 1))
      fi
      ;;
    absent)
      if grep -Eiq "$pattern" "$output"; then
        echo "fixture produced guarded false positive: $name — $description" >&2
        cat "$output" >&2
        failed=$((failed + 1))
      fi
      ;;
  esac

  rm -rf "$tmp"
done < "$MANIFEST"

[ "$failed" -eq 0 ] || { echo "$failed behavioral fixture(s) failed" >&2; exit 1; }
echo "all model-based reviewer fixtures passed"
