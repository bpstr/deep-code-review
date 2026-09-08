# Changelog

## 1.1.0 — 2026-09-08

- Persist review runs outside temporary storage so shutdowns, crashes, and OOM termination do not erase completed work.
- Resume matching interrupted runs with per-stage completion markers; only unfinished reviewers/stages are rerun.
- Isolate simultaneous identical reviews with live run locks while reclaiming stale locks after interruption or reboot.
- Save completed reports, reviewer outputs, logs, confidence files, and resource plans; add `--list-runs` and `--latest-artifacts` discovery.
- Adapt concurrency to available memory and repository size, with conservative caps for 20k+ and 100k+ tracked-file repositories.
- Record the selected resource plan with every run and allow explicit oversubscription only via `DEEP_REVIEW_ALLOW_MEMORY_OVERSUBSCRIBE=1`.
- Preserve existing accessibility coverage: `accessibility-scanner` remains in `full`, and `a11y` remains available explicitly.
- Add deterministic fake-provider regression tests for interruption recovery, orphan cleanup, simultaneous runs, saved artifacts, and memory-pressure throttling.
