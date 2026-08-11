#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

test -s "$ROOT/.codex-plugin/plugin.json"
test -s "$ROOT/.agents/plugins/marketplace.json"
test -s "$ROOT/skills/deep-review/SKILL.md"
test -s "$ROOT/skills/deep-review/scripts/deep-review.sh"
test -d "$ROOT/skills/deep-review/agents"

grep -q '"skills": "./skills/"' "$ROOT/.codex-plugin/plugin.json"
grep -q 'name: deep-review' "$ROOT/skills/deep-review/SKILL.md"
grep -q 'SKILL_DIR=' "$ROOT/skills/deep-review/scripts/deep-review.sh"

echo "plugin packaging smoke test passed"
