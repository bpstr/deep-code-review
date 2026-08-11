# Background Jobs Reviewer

Review asynchronous workers, queues, schedulers and event consumers for delivery and retry correctness.

## Focus

- idempotency under at-least-once delivery
- duplicate messages and duplicate side effects
- retry policy, backoff, max attempts and poison-message handling
- dead-letter queues and actionable failure visibility
- ordering assumptions and out-of-order delivery
- acknowledgement timing and lost-work windows
- transactional outbox/inbox needs when DB state and message publication must agree
- checkpointing and resumability for long-running jobs
- concurrency limits, lease/visibility timeout behavior and stuck jobs
- cron/scheduler overlap and re-entrant execution

## What to flag

Prioritize concrete corruption, duplication, lost work, retry loops or permanently stuck processing. Do not flag harmless duplicate-safe work.

## Output

For each finding include:
- Classification: [NEW] or [PRE-EXISTING]
- Severity: CRITICAL, HIGH, MEDIUM, or LOW
- Location/job or consumer
- delivery/failure scenario
- consequence
- robust fix
