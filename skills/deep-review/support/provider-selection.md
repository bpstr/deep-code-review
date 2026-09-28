# Native caller and provider selection

Deep Review uses the CLI of the client invoking the skill. Provider-neutral means
that the same orchestration works across clients, not that every client delegates
to Codex. All model-bearing stages use one selected provider: stack profiling,
specialist review, synthesis, extraction, confidence scoring, and final triage.

## Selection contract

Precedence is:

1. An explicit `--provider codex|claude|copilot|grok|gemini`.
2. A concrete `DEEP_REVIEW_PROVIDER` value.
3. With `auto`, `DEEP_REVIEW_CALLER`, supplied by the hosting skill on every call.
4. Only when no caller is supplied, an unambiguous native `CLAUDECODE` or
   `CODEX_THREAD_ID` session marker.

An explicit `--provider auto` overrides a concrete environment provider and opts
back into caller resolution. The caller hint beats inherited outer-session
markers: a Grok session launched from a Codex terminal is still Grok when the
skill binds `DEEP_REVIEW_CALLER=grok`.

Supported IDs are `codex`, `claude`, `copilot`, `grok`, and `gemini`. The ID names the
executable, not a model served through some other executable. An unsupported host
must report unsupported execution rather than pretending Codex is a generic
backend. Add a native adapter and routing tests before supporting another CLI.

Installed executables, installation paths such as `.codex/skills`, configuration
directories, API keys, and model names are not caller identity signals. Unknown or
conflicting identity exits with usage error 2. A missing selected CLI exits 127
outside CI. Authentication, policy, availability, and execution failures never
cause a provider switch. CI continues to report operational/incomplete failures
through its existing error-reporting contract.

The durable wrapper resolves once, fingerprints the selected provider, records it
in `request.txt`, and pins it when launching the engine. Every worker goes through
that provider's lifecycle shim, retaining slot limits, timeouts, cancellation,
checkpointing, and provider-labeled lifecycle states. Changing providers cannot
reuse another provider's incomplete review. The fingerprint schema was advanced
to avoid recovering runs created with the former routing behavior.

## Skill invocation

The skill determines its actual host and binds it explicitly on every tool call:

```bash
# Inside Grok Build:
DEEP_REVIEW_CALLER=grok bash "$SKILL_DIR/scripts/deep-review.sh" --target /projects/app full

# Inside Claude Code:
DEEP_REVIEW_CALLER=claude bash "$SKILL_DIR/scripts/deep-review.sh" --changes tests

# Inside Gemini CLI:
DEEP_REVIEW_CALLER=gemini bash "$SKILL_DIR/scripts/deep-review.sh" --target /projects/app arch
```

Only a deliberate user/provider configuration may select a different CLI. Do not
work around a failure by adding `--provider codex`, installing a substitute,
changing authentication, or bypassing a managed permission policy.

## Terminal and CI migration

The previous `auto` behavior preferred installed Codex, then Claude. That behavior
was a defect and has been removed. A normal terminal has no inherent agent
identity, even when only one supported CLI is installed; select it explicitly:

```bash
bash skills/deep-review/scripts/deep-review.sh --provider grok --target /projects/app full
bash skills/deep-review/scripts/deep-review.sh --provider claude --changes tests
bash skills/deep-review/scripts/deep-review.sh --ci --provider copilot --base main full
```

CI still requires a concrete provider and a base ref for branch reviews; a caller
hint does not weaken that requirement. Inspection-only options such as `--help`,
`--version`, `--latest-result`, and `--list-runs` do not require a provider.

Model selection remains optional. `--model` and `--fast-model` are passed only to
the selected CLI; no Codex model ID is injected into Grok, Claude, or Gemini.
Authentication is owned by each installed CLI. Updating this repository does not
update already copied/cached skill installations: refresh the installed skill,
including all bundled scripts and the updated `SKILL.md`.

Output location is unrelated to provider selection. Local reports remain at
`<resolved-target-root>/.deep-review/`, including non-Git targets and invocations
from another working directory. Explicit output and CI/cloud overrides retain
their existing behavior.

## Native adapters and limits

Grok Build uses `grok -p`, optional `--model`, `--no-auto-update`, a read-only sandbox
profile, and explicit file/inspection tool grants. That profile permits temporary
artifact writes; a custom temporary directory must also be permitted by the
installed sandbox. Do not retry without the sandbox when the profile is unavailable.

Gemini uses `gemini -p`, optional `--model`, `--approval-mode auto_edit`, and includes
the skill and temporary artifact directories. This permits artifact editing but
is not an OS sandbox or blanket shell approval. Workspace-trust and managed
policies remain in force. Neither adapter uses `--yolo` or resumes a shared CLI
conversation. Use trusted/disposable workspaces; prompt-level source-write
restrictions are not an OS security boundary, especially for projects in temp.

CLI references checked for this change:

- [Grok headless scripting](https://docs.x.ai/build/cli/headless-scripting)
- [Grok CLI reference](https://docs.x.ai/build/cli/reference)
- [Grok permissions](https://docs.x.ai/build/features/permissions)
- [Grok sandbox](https://docs.x.ai/build/features/sandbox)
- [Gemini CLI options](https://geminicli.com/docs/cli/cli-reference/)

`python3 scripts/test-provider-selection.py` runs credential-free native-command
doubles against the actual wrapper, engine, and lifecycle shims. It verifies
routing with all five competing CLIs installed, every pipeline stage, model/argv
preservation, direct-engine calls, nested-session hints, fail-closed behavior,
provider-separated recovery, CI selection requirements, and target/output roots.
These tests validate orchestration, not authenticated live-provider behavior or
model review quality.
