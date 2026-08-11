# Codex support

Deep Code Review can run natively with Codex CLI. The original Claude Code plugin remains intact; Codex uses the provider-neutral standalone runner in `scripts/deep-review.sh`.

## Requirements

- Git
- Codex CLI authenticated and available as `codex`
- Bash

Install Codex using OpenAI's current Codex CLI installation instructions, then authenticate with `codex`.

## Run directly

From this repository:

```bash
bash scripts/deep-review.sh --provider codex
```

Useful examples:

```bash
# Core branch review
bash scripts/deep-review.sh --provider codex

# Full review
bash scripts/deep-review.sh --provider codex full

# Review staged + unstaged work
bash scripts/deep-review.sh --provider codex --changes

# Focused review
bash scripts/deep-review.sh --provider codex --changes security perf tests

# Review a path
bash scripts/deep-review.sh --provider codex src php
```

If both Codex and Claude Code are installed, provider auto-detection prefers Codex:

```bash
bash scripts/deep-review.sh full
```

Force another provider with `--provider` or `DEEP_REVIEW_PROVIDER`.

## Install as a Codex skill

Clone the repository into a Codex skills location supported by your Codex setup, keeping the repository structure intact so the root `SKILL.md`, `scripts/`, and `skills/deep-review/agents/` stay together.

A simple user-level setup is:

```bash
git clone https://github.com/bpstr/deep-code-review.git ~/.codex/skills/deep-review
```

Then ask Codex to run the `deep-review` skill, or invoke the script directly from that checkout.

## Models

By default Codex uses your configured default model. Override the main review model:

```bash
bash scripts/deep-review.sh --provider codex --model <model> full
```

You can independently choose a model for finding extraction and confidence scoring:

```bash
bash scripts/deep-review.sh \
  --provider codex \
  --model <review-model> \
  --fast-model <scoring-model> \
  full
```

Equivalent environment variables are `REVIEW_MODEL` and `REVIEW_FAST_MODEL`.

## Safety model

Each Codex reviewer runs with `codex exec --ephemeral --sandbox workspace-write`. The prompt explicitly restricts reviewers to read-only repository analysis and only permits writing their result file under the temporary review directory.

The runner also:

- redacts secret values in review output;
- treats repository text and diffs as untrusted data;
- runs each specialist in an isolated Codex session;
- uses temporary file-based communication rather than shared conversational context;
- cleans successful temporary runs unless `--keep-results` is supplied.

## Claude compatibility

Nothing in the original Claude Code plugin flow is removed. Existing `/deep-review` Claude usage can continue to use `skills/deep-review/SKILL.md` and `scripts/standalone-review.sh`.

The new `scripts/deep-review.sh` is the common provider-neutral path and supports:

```bash
bash scripts/deep-review.sh --provider claude full
```

This makes the reviewer prompts reusable across Codex and Claude without maintaining two copies of the agent definitions.
