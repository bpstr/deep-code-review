#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SKILL="$ROOT/skills/deep-review"
ENGINE="$SKILL/scripts/deep-review-engine.sh"
bash -n "$ENGINE"
bash -n "$SKILL/scripts/backend-stack-detection.sh"
for agent in drupal laravel django spring; do
  for term in Classification Location Severity Validation 'Primary sources'; do
    grep -Fq "$term" "$SKILL/agents/$agent-reviewer.md"
  done
  grep -Fq "$agent-reviewer" "$SKILL/SKILL.md"
done
grep -Fq 'SECURE_BROWSER_XSS_FILTER in 4.0' "$SKILL/agents/django-reviewer.md"
grep -Fq 'Since Spring 6.0' "$SKILL/agents/spring-reviewer.md"
grep -Fq 'ALL_EXCEPTIONS' "$SKILL/agents/spring-reviewer.md"
grep -Fq 'after_commit' "$SKILL/agents/laravel-reviewer.md"
grep -Fq 'bubbleable metadata' "$SKILL/agents/drupal-reviewer.md"
grep -Fq 'backend-stack-detection.sh' "$SKILL/scripts/review-cache.sh"
grep -Fq 'framework-review.md' "$SKILL/scripts/review-cache.sh"
grep -Fq 'Backend frameworks' "$SKILL/support/stack-profiler.md"
# Exercise actual selector/profile/control flow with a failing stub, not a model.
TMP="$(mktemp -d "${TMPDIR:-/tmp}/framework-contract.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/repo"
cat >"$TMP/bin/codex" <<'MOCK'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$MOCK_PROMPTS"
exit 1
MOCK
chmod +x "$TMP/bin/codex"
cd "$TMP/repo"
git init -q
git config user.name Fixture
git config user.email fixture@example.invalid
printf '%s\n' '{"require":{"laravel/framework":"^12.0"}}' >composer.json
printf '%s\n' '<?php' >app.php
git add .
git commit -qm fixture
export PATH="$TMP/bin:$PATH" MOCK_PROMPTS="$TMP/prompts"
run_case() {
  : >"$MOCK_PROMPTS"
  local status=0
  DEEP_REVIEW_AUTO_SPECIALISTS=1 TMPDIR="$TMP" bash "$ENGINE" --provider codex --max-concurrent 64 . "$@" >"$TMP/output" 2>&1 || status=$?
  test "$status" -eq 1
  # Failure is intentionally from the provider, not bad shell syntax or selection.
  grep -Fq 'Synthesis failed.' "$TMP/output"
  grep -Fq 'framework-review.md' "$MOCK_PROMPTS"
}
for aspect in drupal laravel spring spring-boot; do
  run_case "$aspect"
  agent="$aspect"; [ "$aspect" != spring-boot ] || agent=spring
  grep -Fq "/$agent-reviewer.md" "$MOCK_PROMPTS"
  grep -Fq 'Read stack profiling instructions' "$MOCK_PROMPTS"
done
run_case core
if grep -Fq 'Read stack profiling instructions' "$MOCK_PROMPTS"; then exit 1; fi
if grep -Fq '/laravel-reviewer.md' "$MOCK_PROMPTS"; then exit 1; fi
run_case --no-auto-specialists full
if grep -Fq 'Read stack profiling instructions' "$MOCK_PROMPTS"; then exit 1; fi
if grep -Fq '/laravel-reviewer.md' "$MOCK_PROMPTS"; then exit 1; fi
run_case full
grep -Fq '/laravel-reviewer.md' "$MOCK_PROMPTS"
grep -Fq '/php-reviewer.md' "$MOCK_PROMPTS"
grep -Fq 'Read stack profiling instructions' "$MOCK_PROMPTS"
echo 'framework contracts passed (7 engine cases; no model calls)'
