#!/usr/bin/env bash
set -euo pipefail

bash -n scripts/deep-review.sh
output="$(bash scripts/deep-review.sh --help)"
grep -q -- '--provider codex|claude|auto' <<<"$output"
grep -q -- '--changes' <<<"$output"
grep -q -- 'CONFIDENCE_THRESHOLD' <<<"$output"
echo "deep-review runner smoke test passed"
