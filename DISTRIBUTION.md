# Deep Code Review distribution

Deep Code Review ships one canonical installable skill at `skills/deep-review/`.

Supported distribution methods:

- Codex plugin via `.codex-plugin/plugin.json`
- repo marketplace via `.agents/plugins/marketplace.json`
- Open Agent Skills CLI via `npx skills add bpstr/deep-code-review --skill deep-review`

The skill directory must stay self-contained. `skills/deep-review/scripts/deep-review.sh` is the public durable runner; `deep-review-engine.sh` preserves the provider-neutral review engine, and the two small shim scripts provide sandbox-safe checkpointing/resource coordination. Reviewer prompts remain under `skills/deep-review/agents/`.

## Version 1.2.0

The Codex/agent plugin version is `1.2.0`. Existing installs can update through their normal plugin update flow after refreshing the `bpstr/deep-code-review` marketplace source. The Claude-compatible manifest is `5.10.0`.

Version 1.2 focuses on execution efficiency and portable result persistence. Confidence validation is batched (four findings per fast-model call by default), specialist detection reuses cached file/manifest discovery, background workers remove an unnecessary shell process, and provider-slot polling reacts faster. Committed branch reviews also avoid hashing unrelated dirty working-tree state when computing recovery identity.

The final report is always saved as `artifacts/review.md` and remains the runner's stdout result, so interactive agents can show the report directly while automation receives a stable file. `--output FILE` / `DEEP_REVIEW_RESULT_FILE` atomically export to one exact path; `--results-dir DIR` / `DEEP_REVIEW_RESULTS_DIR` create a uniquely named result plus `latest.md`. `--latest-result` locates the canonical saved report.

Recovery state and result exports are intentionally separate. Local runs prefer XDG/HOME private state. CI/cloud runs without an explicit state root prefer `RUNNER_TEMP`; if no stable job temp directory exists they create a private random temp root rather than trusting a predictable shared `/tmp` path. Set `DEEP_REVIEW_STATE_DIR` explicitly when later invocations need recovery/discovery. `DEEP_REVIEW_RESULTS_DIR` can point at a secured mounted volume or artifact staging directory. Persistent recovery state can also be mounted, but it should be namespaced per runner/process environment instead of one live namespace shared concurrently across unrelated hosts.

Machine-level provider-slot locks are kept on a separate local runtime filesystem (`DEEP_REVIEW_SLOT_DIR` can override it). This matters for cloud deployments: PID and boot-identity locks must not live on NFS or another cross-host state/result volume. Files are created under `umask 077`, result exports use atomic same-directory replacement, and report contents are never written into CI output metadata.

When GitHub Actions provides `GITHUB_OUTPUT`, the runner publishes only `deep_review_result` and `deep_review_artifacts` paths so a later step can upload or consume the files safely.

Provider processes continue writing only to a temporary sandbox-writable work directory; the outer runner checkpoints completed stages into private persistent state and restores those checkpoints after a crash, shutdown, OOM kill, or other interruption. Simultaneous runs also share a machine-level provider-slot budget so multiple individually safe reviews cannot collectively overcommit memory.

Accessibility review remains part of `full` and is available directly as `a11y`.
