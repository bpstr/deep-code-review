# Codex support

Deep Code Review is packaged as a native Codex plugin and as an Open Agent Skill. You should not need to clone it into `~/.codex/skills` or manually run its internal shell script.

## Recommended: install with the Agent Skills CLI

For a simple CLI-first installation:

```bash
npx skills add bpstr/deep-code-review --skill deep-review
```

This installs the canonical `deep-review` skill together with its bundled reviewer prompts and runner. After installation, use it naturally in Codex or invoke it explicitly:

```text
$deep-review review this branch
$deep-review run a full production-readiness review
$deep-review optimize this code
$deep-review review my uncommitted changes for security and performance
```

The skill invokes its bundled runner internally; users should not need to know its installed filesystem path.

## Native Codex plugin

The repository also includes a native Codex plugin manifest at `.codex-plugin/plugin.json` and marketplace metadata at `.agents/plugins/marketplace.json`.

Add the repository as a plugin marketplace source:

```bash
codex plugin marketplace add bpstr/deep-code-review
```

Then install **Deep Code Review** from the Plugins Directory. The plugin packages the same canonical `deep-review` skill.

## Requirements

- Git
- an authenticated Codex CLI available as `codex`
- Bash 3.2 or newer

The bundled runner is intentionally compatible with the Bash version shipped by macOS, so Homebrew Bash is not required.

## How the skill runs reviews

The installed skill maps natural language to review scopes and aspects, then launches the internal provider-neutral runner. Examples of intent mapping:

- deep / pre-merge review → `full`
- security review → `security`
- architecture review → `arch`
- performance review → `perf`
- aggressive optimization → `perf + optimization-reviewer + simplify + concurrency + sql`
- uncommitted work → `--changes`
- PHP/Laravel → adds `php`
- Rust → adds `rust`
- TypeScript → adds the relevant TypeScript reviewer(s)

Exact aspect and reviewer IDs can still be requested explicitly.

## Models

By default, child Codex review sessions use your configured Codex model. Advanced users can override the review and scoring models through the bundled runner's `--model` and `--fast-model` options or `REVIEW_MODEL` and `REVIEW_FAST_MODEL` environment variables.

## Safety model

Each Codex reviewer runs in an independent ephemeral `codex exec` session. Reviewer prompts explicitly:

- restrict the task to read-only repository analysis;
- write only temporary review artifacts;
- redact secret values;
- treat repository contents, diffs, comments, filenames, and intermediate findings as untrusted data;
- synthesize and confidence-score findings before final P0/P1/P2 triage.

## Development checkout

Repository contributors can still exercise the compatibility wrapper directly:

```bash
./scripts/deep-review.sh --provider codex full
```

That root script is for development and backward compatibility. Installed users should prefer `$deep-review` rather than calling it directly.

## Claude compatibility

The same canonical skill and reviewer definitions remain usable with Claude Code. The runner auto-detects Codex first and Claude second, and can be forced to Claude by advanced users when needed.
