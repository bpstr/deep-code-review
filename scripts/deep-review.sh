#!/usr/bin/env bash
set -euo pipefail

# Compatibility wrapper for repository checkouts. Installed skills should invoke
# skills/deep-review/scripts/deep-review.sh directly through SKILL.md.
exec bash "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/skills/deep-review/scripts/deep-review.sh" "$@"
