# Changelog

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
