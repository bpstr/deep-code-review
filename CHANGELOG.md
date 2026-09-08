# Changelog

## 1.2.0 — 2026-09-08

- Batch confidence validation by default (four findings per fast-model call) to reduce provider startup/token overhead while preserving per-finding scores and resumable batch checkpoints.
- Cache changed-file and manifest discovery during specialist routing instead of repeatedly walking and grepping the same repository metadata.
- Run provider stages through directly killable shim jobs, removing background shell overhead and ensuring cancellation reaches synchronous and parallel providers so resource slots are released promptly.
- Reduce slot-poll latency from one second to 200 ms so newly available provider capacity is used sooner during large reviews.
- Scope durable fingerprints to the data actually reviewed: committed branch reviews no longer hash the entire dirty working tree, while path reviews continue hashing the requested path contents.
- Always persist the final Markdown report as `artifacts/review.md` while continuing to stream that report to stdout for interactive callers.
- Add atomic `--output FILE` and `--results-dir DIR` exports plus `DEEP_REVIEW_RESULT_FILE`, `DEEP_REVIEW_RESULTS_DIR`, and `--latest-result` discovery.
- Add CI/cloud-safe state defaults that prefer job-local temporary storage when HOME should not be assumed writable, while allowing mounted/persistent storage through explicit state/results paths.
- Keep provider PID/boot slot coordination on a machine-local runtime filesystem instead of persistent/shared cloud state volumes; add `DEEP_REVIEW_SLOT_DIR` for explicit local placement.
- Avoid duplicate staged diff work in `--changes`, and keep saved `review.md` byte-for-byte aligned with the stdout report including review-gap annotations.
- Publish result/artifact paths through GitHub Actions `GITHUB_OUTPUT` when available without placing report contents in CI metadata.
- Avoid duplicate checkpoint-to-artifact writes during final persistence by copying the current work tree once and filling only missing files from durable checkpoints.
- Add deterministic efficiency/output regression coverage for batching, batch recovery, clean stdout, exports, scope-aware fingerprints, and CI storage defaults.

## 1.1.1 — 2026-09-08

- Publish run ownership atomically so a shutdown cannot strand an ownerless lock that blocks future recovery.
- Invalidate synthesis, extraction, confidence, and final checkpoints when an upstream stack/reviewer stage has to rerun, preventing stale reports after a transient reviewer failure recovers.
- Remove stale unmarked stage outputs before rerunning them so a provider failure cannot be mistaken for success because an old checkpoint file was restored.
- Include untracked path contents in the durable-run fingerprint, preventing stale path-review recovery after an untracked file changes.
- Make the recovery/resource regression harness part of the standard runner smoke gate and extend it for dependency invalidation and atomic lock ownership.

## 1.1.0 — 2026-09-08

- Persist completed review stages outside reboot-sensitive temporary storage while keeping provider writes inside sandbox-writable temporary directories.
- Resume matching interrupted runs with per-stage completion markers; only unfinished reviewers/stages are rerun.
- Isolate simultaneous identical reviews with live PID + boot-identity run locks while reclaiming stale interrupted runs.
- Save final reports, reviewer outputs, logs, confidence files, checkpoints, and resource plans; add `--list-runs` and `--latest-artifacts` discovery.
- Adapt per-run concurrency to available memory and repository size, with conservative caps for 20k+ and 100k+ tracked-file repositories.
- Share a machine-level provider-slot budget across simultaneous runs so combined review fan-out cannot exceed the calculated memory budget.
- Forward shutdown signals through the runner/provider hierarchy and recover stale slots after process loss or reboot.
- Create persistent review state with private permissions and record the chosen resource plan with every run.
- Preserve existing accessibility coverage: `accessibility-scanner` remains in `full`, and `a11y` remains available explicitly.
- Add deterministic fake-provider regression tests for interruption recovery, sandbox-safe persistence, orphan cleanup, simultaneous runs, global memory throttling, saved artifacts, and low-memory per-run throttling.
