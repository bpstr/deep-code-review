# CI guide

Use the public `scripts/deep-review.sh` entrypoint from a trusted installation or pinned checkout. It orchestrates the same isolated specialists, synthesis, confidence checks, and final triage used interactively. Run it directly from the CI shell with a preauthenticated provider; an additional agent is not needed to launch it.

## GitHub Actions setup

Copy either [the Codex workflow](https://github.com/bpstr/deep-code-review/blob/main/examples/github-actions/codex.yml) or [the Copilot workflow](https://github.com/bpstr/deep-code-review/blob/main/examples/github-actions/copilot.yml) into `.github/workflows/deep-review.yml` in the repository being reviewed.

Configure these repository variables under **Settings → Secrets and variables → Actions → Variables**:

| Variable | Value |
| --- | --- |
| `DEEP_REVIEW_REF` | A full 40-character commit SHA of a reviewed Deep Code Review version containing `--ci` support. Select the commit from `bpstr/deep-code-review`; a branch name or moving tag is rejected. |
| `CODEX_CLI_VERSION` | For the Codex example: an exact published `@openai/codex` version, such as a tested stable release from [Codex releases](https://github.com/openai/codex/releases). |
| `COPILOT_CLI_VERSION` | For the Copilot example: an exact published `@github/copilot` version with GitHub Actions token support, such as `1.0.86`, whose required CLI flags were verified. See [Copilot CLI releases](https://github.com/github/copilot-cli/releases). |

Configure authentication for the selected provider as described below. Open a same-repository PR from a trusted contributor to exercise the job. The example starts with `core`, at most two concurrent provider workers, and `--fail-on none`. After checking the reports against real changes, choose a blocking threshold if useful.

The workflow checks out the PR's **head SHA** with complete Git history, verifies that its **base SHA** is available, and passes that base explicitly. Branch reviews use the merge-base diff, so the report covers the changes introduced by the PR. The trusted review tool is a separate checkout at `DEEP_REVIEW_REF`, outside the source repository. Both checkouts disable persisted Git credentials. See the official [checkout documentation](https://github.com/actions/checkout#usage) for these inputs.

The templates target disposable GitHub-hosted Ubuntu runners. They pin GitHub actions by commit, disable dependency caching, install only the selected provider CLI, and publish the final reports before applying the saved review exit code. They do not run the reviewed project's install hooks, builds, or tests.

## Codex authentication and the official action

Create an Actions secret named `OPENAI_API_KEY`. The example exposes it as `CODEX_API_KEY` only to the review step. `codex exec` supports this noninteractive authentication directly, so an interactive login or a copied personal login session is unnecessary. The calls use API billing. See [Codex authentication in automation](https://learn.chatgpt.com/docs/non-interactive-mode).

The official [`openai/codex-action`](https://github.com/openai/codex-action) is useful for a single Codex invocation: it installs and authenticates Codex, accepts a prompt and optional output schema, and applies its own API-proxy and privilege protections. A review prompt passed to that action does not automatically run Deep Code Review's specialist, synthesis, and scoring stages.

Our Codex example calls the runner directly to preserve that complete pipeline and its deterministic report validation and exit codes. It does **not** inherit `codex-action`'s proxy or privilege protections. Do not use the action merely as an installer and assume later child CLI processes receive those protections, or launch the runner inside another Codex session. A single-reviewer action workflow is a separate integration with different coverage and outputs.

## Copilot authentication

The Copilot example grants `contents: read` and `copilot-requests: write`, then exposes the job's `${{ github.token }}` as `GITHUB_TOKEN` only to the review step. No PAT is needed for this native GitHub Actions authentication path. A personal repository uses the owner's eligible Copilot seat; an organization must enable **Allow use of Copilot CLI billed to the organization** and have the required Copilot access and budget. Token permissions alone do not enable billing. See [Copilot CLI in GitHub Actions](https://docs.github.com/en/copilot/concepts/agents/copilot-cli/copilot-cli-in-github-actions) and [the setup instructions](https://docs.github.com/en/copilot/how-tos/copilot-cli/use-copilot-cli-in-actions).

The template uses Node 24, a pinned npm CLI version, an isolated `COPILOT_HOME`, and `COPILOT_AUTO_UPDATE=false`. GitHub's [npm installation instructions](https://docs.github.com/en/copilot/how-tos/copilot-cli/set-up-copilot-cli/install-copilot-cli) require Node 22 or newer. The runner selects Copilot only when explicitly requested with `--provider copilot`; existing provider auto-detection remains Codex then Claude.

This integration uses **Copilot CLI in a workflow**. GitHub's built-in Copilot code review and Copilot coding agent are separate products and do not automatically execute this review pipeline.

`actionlint` 1.7.12 does not yet recognize the documented `copilot-requests` permission. If that is the only diagnostic, keep the required permission and use this narrow schema-compatibility exclusion while linting the template:

```bash
actionlint -ignore 'unknown permission scope "copilot-requests"' \
  .github/workflows/deep-review.yml
```

## Running on any CI platform

Requirements are Bash 3.2+, Git, Python 3, and an installed, authenticated provider CLI. Python is used for local CI report validation and rendering; no Python package installation is required. Run from the root of the repository being reviewed, with its reviewed head checked out and the base commit available:

```bash
# SKILL_DIR points to the trusted installed skill or pinned tool checkout.
# REVIEW_BASE_SHA identifies the base commit from the CI event.
# REVIEW_REPORT_DIR and REVIEW_STATE_DIR are private, writable job directories.
bash "$SKILL_DIR/scripts/deep-review.sh" \
  --ci \
  --provider codex \
  --base "$REVIEW_BASE_SHA" \
  --max-concurrent 2 \
  --artifacts-dir "$REVIEW_STATE_DIR" \
  --output "$REVIEW_REPORT_DIR/review.md" \
  --fail-on p1 \
  core
```

Select `codex`, `claude`, or `copilot` explicitly through `--provider` or `DEEP_REVIEW_PROVIDER`. CI mode rejects `auto`. Branch scope also requires an explicit `--base` or `REVIEW_BASE`; CI mode does not guess a default branch. `--changes` and path scopes remain available when the job deliberately prepares that scope.

`--ci` starts a fresh review and disables resuming earlier runs. It validates structured findings and stage completion before deciding the result. `--fail-on` is a CI control; ordinary interactive invocations keep their existing behavior.

| `--fail-on` | Findings that fail a completed review |
| --- | --- |
| `none` (default) | None; report findings without a severity gate |
| `p0` | New P0 findings |
| `p1` | New P0 or P1 findings |
| `p2` | New P0, P1, or P2 findings |

Only **NEW**, included findings that pass confidence filtering count toward the gate. PRE-EXISTING findings can appear in the report without blocking a PR. Severity gating uses validated structured data rather than searching Markdown for strings such as `P1`.

| Exit code | Meaning |
| --- | --- |
| `0` | Review completed and passed the chosen gate, including a valid no-changes result |
| `1` | Operational failure or incomplete review, including failed stages or invalid structured output |
| `2` | Invalid usage or missing required CI options |
| `3` | Review completed, but new findings met the configured threshold |

`--fail-on none` still fails on incomplete analysis, invalid output, and operational errors. It means advisory findings, not an unconditional green job.

## Reports and workflow outputs

The run keeps canonical `artifacts/review.md` and `artifacts/review.json` files. With `--output /path/review.md`, it exports both `/path/review.md` and `/path/review.json`. `--results-dir` also exports per-run files and `latest.md` / `latest.json`.

| GitHub Actions step output | Value |
| --- | --- |
| `deep_review_result` | Final Markdown report path |
| `deep_review_json` | Validated CI JSON report path |
| `deep_review_artifacts` | Run artifact directory |

Outputs contain paths, not report bodies. Reports are preserved on a severity-gate failure; on incomplete runs the runner emits the available status/report artifacts when possible. Errors before initialization, abrupt runner loss, or cancellation can leave no report. Always retain the process exit status as well as the report.

The JSON report has `schema_version: 1` and `status` equal to `complete`, `no_changes`, or `error`. `findings` includes classification, source/location, confidence, normalized priority, and `included` for every extracted finding. `gate` records `fail_on`, the matching NEW `finding_ids`, and `passed`. It also records the reviewed base/head and provider. Treat the schema version as part of the integration contract; use the runner's exit code for a simple CI gate rather than rebuilding threshold logic in YAML.

The examples upload only final Markdown/JSON reports, with seven-day retention. Raw prompts, provider logs, recovery state, credentials, and CLI configuration are kept out of the uploaded artifact. Reports can still contain proprietary code references: job summaries and artifacts follow repository access, so review that visibility before enabling a public job.

The runner's stdout/stderr is redirected to a private job-local log so model text cannot be interpreted as Actions workflow commands. Failed-stage reports provide a concise failure reason. When that is insufficient, a maintainer can deliberately retain a diagnostic artifact with appropriate access and redaction; the templates do not publish raw diagnostics automatically.

## Trust, cost, and coverage

Automatic examples run only on non-draft, same-repository PRs associated with an owner, member, or collaborator; they skip forks and Dependabot PRs. Treat these as trusted-contributor workflows. This filtering does not establish that arbitrary repository code, local provider configuration, or MCP servers are safe to execute.

Source code and review intermediates are untrusted inputs to the model. Providers receive instructions to review without changing source, but the runner needs artifact writes; this is **not an OS-enforced read-only source boundary**. Keep the runner disposable, provide only the selected provider credential, and keep the review-tool pin under maintainer control. The source checkout's own review script must not replace the trusted tool.

Do not change the trigger to `pull_request_target` to obtain secrets for a fork checkout. For external contributions, use an independently designed maintainer-triggered workflow with explicit reviewed SHAs and appropriate isolation. See GitHub's [secure use guidance](https://docs.github.com/en/actions/security-for-github-actions/security-guides/security-hardening-for-github-actions).

**Skipped PRs receive no AI review. GitHub reports skipped jobs as successful for required-check purposes**, so marking either example job as required does not enforce review of forks or Dependabot PRs. Keep the job advisory until a separate trusted/manual process and required-check policy cover those cases. See GitHub's [job-condition documentation](https://docs.github.com/en/actions/how-tos/write-workflows/choose-when-workflows-run/control-jobs-with-conditions).

The templates cover local source and Git history through `core`. Extend that coverage with explicit local aspects such as `security tests` or the relevant language/framework reviewers. They do not execute the application's test suite or install analysis dependencies; reports must distinguish code inspection from executed verification.

`full` additionally includes `prior-feedback-reviewer`, which needs historical GitHub PR comments through authenticated `gh` access. The supplied Codex job has no GitHub CLI credential, and the Copilot provider's restricted shell policy does not allow `gh` or a GitHub MCP server. Using `full` therefore requires a separate design for the required external context, authentication, and tool access. Missing required coverage must be reported as an incomplete CI review, rather than silently interpreted as no findings.

Each review makes multiple provider calls. `--max-concurrent 2` limits simultaneous workers, not total usage. Use provider-side budgets, the workflow timeout, and `DEEP_REVIEW_PROVIDER_TIMEOUT_SECONDS` to bound resource use. Optional `--model` / `--fast-model` or `REVIEW_MODEL` / `DEEP_REVIEW_FAST_MODEL` select models available to the authenticated provider; without them the CLI's configured/default model is used.
