# Deep Code Review installation

Deep Code Review is distributed as both a Codex plugin and an Open Agent Skill.

## Codex plugin

Codex plugins are the preferred distribution format for reusable capabilities. This repository includes a `.codex-plugin/plugin.json` manifest and a repo marketplace entry.

Add this repository as a marketplace source:

```bash
codex plugin marketplace add bpstr/deep-code-review
```

Then install **Deep Code Review** from the Plugins Directory. After installation, invoke it naturally or explicitly with `$deep-review` in Codex.

## Open Agent Skills / npx

The repository is also compatible with the open Agent Skills CLI:

```bash
npx skills add bpstr/deep-code-review --skill deep-review
```

This installs the self-contained `deep-review` skill, including its reviewer definitions and runner. You do not need to clone the repository or run a script from `~/.codex/skills` manually.

## Usage

After installation, ask Codex for a deep review, production-readiness review, security review, optimization review, or another supported review mode. Codex should activate the skill from its description. You can also invoke it explicitly:

```text
$deep-review review this branch
$deep-review run a full review
$deep-review optimize this code
$deep-review review uncommitted changes for security and performance
```

The skill owns its internal orchestration. The shell runner is an implementation detail bundled inside the installed skill.
