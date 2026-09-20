# Continuous integration

Deep Code Review can run its complete specialist, synthesis, confidence-scoring, and triage pipeline as a noninteractive CI job. CI mode produces Markdown and validated JSON reports and can fail a job when new findings meet a chosen severity threshold.

Copy one of these workflows into the repository you want to review:

| Provider | Workflow | Authentication |
| --- | --- | --- |
| OpenAI Codex CLI | [`codex.yml`](examples/github-actions/codex.yml) | `OPENAI_API_KEY` repository secret |
| GitHub Copilot CLI | [`copilot.yml`](examples/github-actions/copilot.yml) | Job-scoped `GITHUB_TOKEN` with `copilot-requests: write`; an eligible owner or organization Copilot billing policy |

The examples are templates, so adding them to this repository does not activate paid review jobs. They start in advisory mode and publish reports to the job summary and a workflow artifact.

See the bundled [CI guide](skills/deep-review/support/ci-guide.md) for setup, provider requirements, exit codes, finding thresholds, report paths, and the trust boundary for automatic PR reviews. It also explains how the official `openai/codex-action` differs from running this multi-stage pipeline.
