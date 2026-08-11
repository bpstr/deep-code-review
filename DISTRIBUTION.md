# Deep Code Review distribution

Deep Code Review ships one canonical installable skill at `skills/deep-review/`.

Supported distribution methods:

- Codex plugin via `.codex-plugin/plugin.json`
- repo marketplace via `.agents/plugins/marketplace.json`
- Open Agent Skills CLI via `npx skills add bpstr/deep-code-review --skill deep-review`

The skill directory must stay self-contained: its runner lives at `skills/deep-review/scripts/deep-review.sh` and reviewer prompts live under `skills/deep-review/agents/`.
