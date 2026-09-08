# Deep Code Review distribution

Deep Code Review ships one canonical installable skill at `skills/deep-review/`.

Supported distribution methods:

- Codex plugin via `.codex-plugin/plugin.json`
- repo marketplace via `.agents/plugins/marketplace.json`
- Open Agent Skills CLI via `npx skills add bpstr/deep-code-review --skill deep-review`

The skill directory must stay self-contained. The public runner is `skills/deep-review/scripts/deep-review.sh`; the provider-neutral review engine is bundled beside it as `deep-review-engine.sh`, with reviewer prompts under `skills/deep-review/agents/`.

## Version 1.1.0

The Codex/agent plugin version is `1.1.0`. Existing installs can update through their normal plugin update flow after refreshing the `bpstr/deep-code-review` marketplace source. The Claude-compatible manifest is bumped to `5.9.0` to preserve its existing version line.

Version 1.1.0 adds durable resumable runs, saved artifacts, simultaneous-run isolation, adaptive memory/concurrency protection for large repositories, and recovery/resource regression coverage. Accessibility review remains part of `full` and is available directly as `a11y`.

Persistent run data defaults to `${XDG_STATE_HOME:-~/.local/state}/deep-code-review`. Use `--list-runs` or `--latest-artifacts` to locate saved reports, or `--artifacts-dir DIR` / `DEEP_REVIEW_STATE_DIR` to choose another location.
