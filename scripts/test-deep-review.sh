#!/usr/bin/env bash
set -euo pipefail

bash -n scripts/deep-review.sh
bash -n skills/deep-review/scripts/deep-review.sh
bash -n scripts/test-runner-resilience.sh

output="$(bash skills/deep-review/scripts/deep-review.sh --help)"
grep -q -- '--provider codex|claude|auto' <<<"$output"
grep -q -- '--changes' <<<"$output"
grep -q -- '--no-auto-specialists' <<<"$output"
grep -q -- '--artifacts-dir DIR' <<<"$output"
grep -q -- '--fresh' <<<"$output"
grep -q -- 'DEEP_REVIEW_AUTO_SPECIALISTS=0' <<<"$output"
grep -q -- 'DEEP_REVIEW_MAX_CONCURRENT' <<<"$output"
grep -q -- 'DEEP_REVIEW_MIN_FREE_MB' <<<"$output"
grep -q -- 'react' <<<"$output"
grep -q -- 'vite' <<<"$output"
grep -q -- 'CONFIDENCE_THRESHOLD' <<<"$output"

bash scripts/test-runner-resilience.sh

echo "deep-review runner smoke test passed"
