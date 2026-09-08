# Deep Code Review distribution

Deep Code Review ships one canonical installable skill at `skills/deep-review/`.

Supported distribution methods:

- Codex plugin via `.codex-plugin/plugin.json`
- repo marketplace via `.agents/plugins/marketplace.json`
- Open Agent Skills CLI via `npx skills add bpstr/deep-code-review --skill deep-review`

The skill directory must stay self-contained. `skills/deep-review/scripts/deep-review.sh` is the public durable runner; `deep-review-engine.sh` preserves the provider-neutral review engine, and the two small shim scripts provide sandbox-safe checkpointing/resource coordination. Reviewer prompts remain under `skills/deep-review/agents/`.

## Version 1.1.1

The Codex/agent plugin version is `1.1.1`. Existing installs can update through their normal plugin update flow after refreshing the `bpstr/deep-code-review` marketplace source. The Claude-compatible manifest is `5.9.1` to preserve its existing version line.

Version 1.1 introduced resumable review checkpoints, saved artifacts, simultaneous-run isolation, and adaptive memory protection. Version 1.1.1 hardens the recovery boundary further: run ownership is atomically published, stale downstream checkpoints are invalidated when an upstream stage reruns, and untracked path contents participate in recovery identity.

Provider processes continue writing only to a temporary sandbox-writable work directory; the outer runner checkpoints completed stages into private persistent state and restores those checkpoints after a crash, shutdown, OOM kill, or other interruption. Simultaneous runs also share a machine-level provider-slot budget so multiple individually safe reviews cannot collectively overcommit memory.

Accessibility review remains part of `full` and is available directly as `a11y`.

Persistent run data defaults to `${XDG_STATE_HOME:-~/.local/state}/deep-code-review` and is created with private permissions. Use `--list-runs` or `--latest-artifacts` to locate saved reports, or `--artifacts-dir DIR` / `DEEP_REVIEW_STATE_DIR` to choose another location.