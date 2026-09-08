# Recovery, concurrency, and saved review artifacts

Deep Code Review 1.1 adds durable orchestration for long reviews. A machine shutdown, terminal interruption, or memory-pressure stop should cost only the provider stage that was actually in flight instead of the whole review.

## Persistent run state

Run state is stored outside the reviewed repository by default:

```text
$XDG_STATE_HOME/deep-code-review/<repo-key>/runs/<run-id>/
```

When `XDG_STATE_HOME` is unset, the default is `~/.local/state/deep-code-review/...`.

Each run keeps:

- `FINAL.md` — final P0/P1/P2 report
- `REPORT.md` — synthesized report before final confidence triage
- `reviewers/*.md` — individual specialist outputs
- `findings/` — extracted findings and confidence scores
- `stack-context.md` and `scope.txt` — shared review context
- `logs/` — provider logs, deliberately separated from reviewer outputs so synthesis does not ingest them
- `checkpoints/` — completion markers for recoverable stages
- `run-info.txt` — provider, scope, agent set, concurrency, and request metadata

Artifacts are preserved after successful runs as well as failed/interrupted runs. Use `--artifacts-dir DIR` or `DEEP_REVIEW_STATE_DIR` to choose another location. Old runs are not deleted automatically; remove old run directories according to your local retention needs.

## Automatic recovery

On startup the runner fingerprints the review inputs: repository/scope snapshot, provider and models, selected reviewers, stack-routing mode, and confidence threshold. If it finds a compatible incomplete run that is not currently active, it resumes that run automatically.

Completed reviewers and later stages are reused only when both their output and completion marker exist. A partially written file without its marker is rerun, so a shutdown cannot turn truncated output into a false checkpoint.

Runtime concurrency and memory-tuning values are intentionally excluded from the recovery fingerprint. After a memory-related interruption you can restart with a smaller value such as:

```bash
$deep-review --max-concurrent 2 full
```

and completed work from the interrupted run is still reused.

Use `--fresh` when you explicitly want a new run instead of resuming compatible work.

## Simultaneous runs

Every run has a unique run directory and an atomic active-run lock. If two identical reviews start at the same time, the second process sees that the first run is live and creates a separate run rather than sharing files or checkpoints.

A lock left behind by a crash or power loss is reclaimed when its recorded process is no longer alive. This lets the next invocation resume the abandoned run.

## Memory-aware execution

The historical fixed default of 12 concurrent provider processes can put unnecessary pressure on large repositories. Version 1.1 uses memory-aware automatic concurrency instead:

- automatic concurrency is capped at 6 by default;
- approximately 1024 MB is budgeted per provider process;
- 1536 MB is reserved for the OS, Git, shell, and repository tooling;
- before every new provider launch, the runner checks available memory where the OS exposes it;
- below the 768 MB free-memory floor, the runner waits for active jobs to finish; if no active job can free memory, it exits with status 75 and leaves a resumable checkpoint rather than pushing the machine further toward OOM.

Controls:

```text
--max-concurrent N
DEEP_REVIEW_MAX_CONCURRENT
DEEP_REVIEW_MEMORY_PER_AGENT_MB
DEEP_REVIEW_MEMORY_RESERVE_MB
DEEP_REVIEW_MIN_FREE_MB
```

The defaults are conservative rather than a hard resource limit. Provider processes can have different memory profiles, so lower `--max-concurrent` further on very large monorepos or memory-constrained machines.

## Additional memory reductions

The runner also avoids two sources of avoidable context and memory amplification:

1. provider logs live under `logs/`, while synthesis reads only `reviewers/`;
2. confidence scorers no longer receive a generated full-repository diff file and are instructed to inspect only the relevant code/diff for each finding.

Changed-file and changed-line metadata is streamed through files rather than retained as large shell variables, and package/manifest discovery results are cached for reuse during routing.

## Accessibility

Accessibility was already part of the stable `full` review set through `accessibility-scanner`, and the explicit `a11y` aspect remains available. Version 1.1 adds a regression assertion so future runner changes cannot silently drop accessibility from full reviews.
