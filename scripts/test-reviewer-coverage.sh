#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AGENTS="$ROOT/skills/deep-review/agents"

required=(
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
done

grep -q 'api-contract-reviewer' "$ROOT/SKILL.md"
grep -q 'database-migration-reviewer' "$ROOT/REVIEWER-COVERAGE.md"
grep -q 'resource-lifecycle-reviewer' "$ROOT/REVIEWER-COVERAGE.md"

echo "reviewer coverage smoke test passed"
