#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AGENTS="$ROOT/skills/deep-review/agents"

required=(
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
  grep -q "$agent" "$ROOT/SKILL.md" || {
    echo "reviewer missing from root skill documentation: $agent" >&2
    exit 1
  }
  grep -q "$agent" "$ROOT/REVIEWER-COVERAGE.md" || {
    echo "reviewer missing from coverage audit: $agent" >&2
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

grep -q 'REVIEWER-COVERAGE.md' "$ROOT/skills/deep-review/SKILL.md"
grep -q 'matching `agents/<selector>.md` file' "$ROOT/skills/deep-review/SKILL.md"

echo "reviewer coverage smoke test passed"
