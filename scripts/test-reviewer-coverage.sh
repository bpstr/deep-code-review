#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AGENTS="$ROOT/skills/deep-review/agents"
SKILL="$ROOT/skills/deep-review/SKILL.md"
RUNNER="$ROOT/skills/deep-review/scripts/deep-review.sh"

required=(
  react-reviewer
  vite-reviewer
  optimization-reviewer
  api-contract-reviewer
  database-migration-reviewer
  observability-reviewer
  resilience-reviewer
  background-jobs-reviewer
  resource-lifecycle-reviewer
)

for agent in "${required[@]}"; do
  test -s "$AGENTS/$agent.md" || {
    echo "missing reviewer: $agent" >&2
    exit 1
  }
  grep -q "$agent" "$SKILL" || {
    echo "reviewer missing from canonical skill documentation: $agent" >&2
    exit 1
  }
  grep -q 'Classification' "$AGENTS/$agent.md" || {
    echo "reviewer missing classification contract: $agent" >&2
    exit 1
  }
  grep -q 'Severity' "$AGENTS/$agent.md" || {
    echo "reviewer missing severity contract: $agent" >&2
    exit 1
  }
  grep -q 'Location' "$AGENTS/$agent.md" || {
    echo "reviewer missing location contract: $agent" >&2
    exit 1
  }
done

grep -q 'react) echo react-reviewer' "$RUNNER"
grep -q 'vite) echo vite-reviewer' "$RUNNER"
grep -q 'detect_specialists' "$RUNNER"
grep -q 'DEEP_REVIEW_AUTO_SPECIALISTS' "$RUNNER"
grep -q 'react-reviewer' "$ROOT/README.md"
grep -q 'vite-reviewer' "$ROOT/README.md"

echo "reviewer coverage smoke test passed"
