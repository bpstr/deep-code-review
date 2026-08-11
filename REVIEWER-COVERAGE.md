# Reviewer Coverage Audit

This audit reviews the current Deep Code Review specialist set and identifies high-value gaps that are not cleanly covered by the existing language, framework, security, performance, concurrency, SQL, testing, architecture, and infrastructure reviewers.

## Existing coverage is already strong

The project already has broad coverage across:

- code quality and silent failure handling
- architecture, dependency cycles, hotspots, consistency and scale
- type design, comments, tests, simplification and accessibility
- localization, concurrency, performance, security and PII
- agent instructions and repository guidelines/history
- frontend/backend TypeScript and major web frameworks
- PHP/Laravel, Rust, Go, Python/Django, Ruby/Rails, Java/Kotlin/Scala, .NET, C/C++ and Elixir
- iOS, macOS, Android, Flutter and React Native
- SQL, GraphQL, Docker, Kubernetes, Terraform, Shell and GitHub Actions

Adding more language-specific reviewers would currently have lower value than filling cross-cutting operational gaps.

## Newly proposed opt-in reviewers

These reviewers are intentionally **not added to `full` yet**. They should first be exercised on real repositories, confidence-scored, and adjusted for overlap/noise. They can already be invoked directly by agent ID because both runners accept an existing agent filename as a selector.

### `api-contract-reviewer`

Covers API and integration compatibility across REST, RPC, webhooks, SDKs, serialized payloads and library-facing contracts.

Why it is distinct: the GraphQL reviewer is protocol-specific, while the general code reviewer does not systematically reason about downstream consumers, coordinated deploy requirements, enum/nullability compatibility, pagination stability or version/deprecation behavior.

Example:

```bash
bash scripts/deep-review.sh --changes api-contract-reviewer
```

### `database-migration-reviewer`

Covers production-safe schema/data evolution: expand/migrate/contract sequencing, locking, backfills, rolling-deploy compatibility, restartability and destructive changes.

Why it is distinct: the SQL reviewer covers query/schema quality broadly, but migration correctness is a deployment-time discipline with failure modes that only appear while old and new application versions coexist.

Example:

```bash
bash scripts/deep-review.sh --changes database-migration-reviewer
```

### `observability-reviewer`

Covers logs, metrics, traces, correlation, health signals, telemetry cardinality and whether changed behavior can actually be diagnosed in production.

Why it is distinct: performance/security reviewers may notice individual logging issues, but neither evaluates whether the system exposes enough reliable telemetry to detect and reconstruct failures.

Example:

```bash
bash scripts/deep-review.sh --changes observability-reviewer
```

### `resilience-reviewer`

Covers network/process-boundary failure handling: timeouts, retry safety, exponential backoff/jitter, cancellation, partial failures, duplicate side effects and graceful degradation.

Why it is distinct: concurrency focuses on simultaneous execution correctness; resilience focuses on dependency failure and failure amplification across boundaries.

Example:

```bash
bash scripts/deep-review.sh --changes resilience-reviewer
```

### `background-jobs-reviewer`

Covers queues, workers, schedulers and event consumers: at-least-once delivery, idempotency, acknowledgement timing, dead letters, ordering, checkpointing, retry loops and cron overlap.

Why it is distinct: these systems have delivery semantics and duplicate/lost-work failure modes that are not reliably caught by generic concurrency or resilience analysis.

Example:

```bash
bash scripts/deep-review.sh --changes background-jobs-reviewer
```

### `resource-lifecycle-reviewer`

Covers ownership and deterministic cleanup of sockets, files, streams, DB connections, transactions, locks, tasks, timers, subscriptions and child processes.

Why it is distinct: performance can identify high resource use and concurrency can identify races/deadlocks, but resource lifetime bugs often require explicit acquire/use/release-path analysis across exceptions, cancellation and shutdown.

Example:

```bash
bash scripts/deep-review.sh --changes resource-lifecycle-reviewer
```

## Suggested validation bundles

Before promoting these into `full`, test them in focused combinations:

```bash
# Production backend changes
bash scripts/deep-review.sh --changes \
  api-contract-reviewer \
  database-migration-reviewer \
  observability-reviewer \
  resilience-reviewer

# Worker / queue changes
bash scripts/deep-review.sh --changes \
  background-jobs-reviewer \
  resilience-reviewer \
  resource-lifecycle-reviewer \
  concurrency

# Deployment-sensitive application change
bash scripts/deep-review.sh --changes \
  database-migration-reviewer \
  api-contract-reviewer \
  security \
  tests
```

## Promotion criteria

Promote a candidate into a named aspect and potentially `full` when:

1. it repeatedly finds issues missed by existing reviewers;
2. its findings survive confidence scoring at a useful rate;
3. overlap with existing agents is low enough to avoid synthesis noise;
4. prompts work across multiple languages/frameworks;
5. runtime/token cost is justified by the severity of issues found.

Potential future aliases after validation:

- `api` → `api-contract-reviewer`
- `migrations` → `database-migration-reviewer`
- `observability` → `observability-reviewer`
- `resilience` → `resilience-reviewer`
- `jobs` → `background-jobs-reviewer`
- `resources` → `resource-lifecycle-reviewer`
- `production` → observability + resilience + migrations + API contracts + resource lifecycle

## Other uncovered areas worth considering later

These look useful, but are lower-confidence candidates because they overlap more heavily with existing reviewers or are domain-specific:

- **cache correctness** — stale reads, invalidation, stampedes, key-space collisions, tenant isolation
- **multi-tenancy isolation** — tenant scoping across DB queries, caches, jobs, storage and authorization
- **CLI ergonomics** — exit codes, stdout/stderr contracts, non-interactive behavior, shell composition
- **feature-flag lifecycle** — stale flags, unsafe default states, inconsistent evaluation and cleanup
- **data retention/compliance** — deletion propagation, retention windows, legal holds, auditability
- **time/date correctness** — timezones, DST, clock assumptions, expiry and scheduling boundaries
- **numerical/financial correctness** — precision, rounding, units, overflow and currency handling
- **search/index consistency** — source-of-truth vs search-index drift, reindex safety and eventual consistency

These should become reviewers only after there are representative repositories/tests to calibrate them against.

## References behind the gap selection

- Martin Fowler's Parallel Change / expand-contract guidance illustrates why compatibility and migration sequencing need explicit review: https://martinfowler.com/bliki/ParallelChange.html
- Evolutionary Database Design discusses backward-compatible database evolution during continuous delivery: https://martinfowler.com/articles/evodb.html
- OpenTelemetry defines observability around correlated traces, metrics and logs: https://opentelemetry.io/docs/concepts/observability-primer/
- AWS Builders' Library documents timeouts, retries, backoff and jitter as core distributed-system reliability concerns: https://aws.amazon.com/builders-library/timeouts-retries-and-backoff-with-jitter/
- Google Cloud job guidance explicitly recommends idempotent job design for retry/restart safety: https://cloud.google.com/run/docs/jobs-retries
