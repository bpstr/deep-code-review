# Changelog

## 1.1.0 — 2026-09-08

Codex plugin version: **1.1.0**. Claude marketplace/plugin version: **5.9.0**.

- add durable per-stage checkpoints and automatic recovery after interruption or shutdown
- preserve review artifacts by default in a persistent per-repository state directory
- make simultaneous identical reviews safe through unique run directories and active-run locks
- replace the fixed concurrency default with memory-aware automatic concurrency and a low-memory safety stop
- isolate provider logs from reviewer outputs so synthesis does not scan large log files
- avoid materializing the complete diff for every confidence-scoring pass
- include untracked files in `--changes` scope and recovery fingerprints
- preserve accessibility review in `full` and add routing regression coverage
- add interruption, concurrent-run, memory-pressure, and accessibility resilience tests
