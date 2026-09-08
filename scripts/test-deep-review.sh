#!/usr/bin/env bash
set -euo pipefail

bash -n scripts/deep-review.sh
bash -n skills/deep-review/scripts/deep-review.sh
bash -n skills/deep-review/scripts/deep-review-engine.sh
bash -n skills/deep-review/scripts/deep-review-provider-shim.sh
bash -n skills/deep-review/scripts/deep-review-mktemp-shim.sh
bash -n scripts/test-deep-review-recovery.sh

output="$(bash skills/deep-review/scripts/deep-review.sh --help)"
grep -q -- '--provider codex|claude|auto' <<<"$output"
grep -q -- '--changes' <<<"$output"
grep -q -- '--no-auto-specialists' <<<"$output"
grep -q -- '--no-resume' <<<"$output"
grep -q -- '--artifacts-dir DIR' <<<"$output"
grep -q -- '--list-runs' <<<"$output"
grep -q -- 'DEEP_REVIEW_MEMORY_PER_WORKER_MB' <<<"$output"
grep -q -- 'DEEP_REVIEW_AUTO_SPECIALISTS=0' <<<"$output"
grep -q -- 'react' <<<"$output"
grep -q -- 'vite' <<<"$output"
grep -q -- 'CONFIDENCE_THRESHOLD' <<<"$output"

version="$(bash skills/deep-review/scripts/deep-review.sh --version)"
[ "$version" = 'Deep Code Review 1.1.1' ]

grep -q 'FULL=.*accessibility-scanner' skills/deep-review/scripts/deep-review-engine.sh
grep -q 'a11y) echo accessibility-scanner' skills/deep-review/scripts/deep-review-engine.sh

bash scripts/test-deep-review-recovery.sh

echo "deep-review runner smoke test passed"