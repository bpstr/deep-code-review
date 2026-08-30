# Deep Code Review

Deep Code Review is a comprehensive multi-agent code review system for **OpenAI Codex** and **Claude Code**.

Instead of asking one model to review everything in one context, it runs focused specialist reviewers, synthesizes their findings, independently confidence-scores them, and produces a final P0/P1/P2 report.

## Install

```bash
npx skills add bpstr/deep-code-review --skill deep-review
```

The installed skill is self-contained: it includes reviewer definitions and its orchestration runner. You do **not** need to clone the repository into a skills directory or manually locate the internal script.

Example usage:

```text
$deep-review review this branch
$deep-review run a full review
$deep-review review my uncommitted changes
$deep-review optimize this code
$deep-review review this React + Vite change
```

The repository also includes a native Codex plugin manifest. See [`INSTALL.md`](INSTALL.md) and [`CODEX.md`](CODEX.md).

## Why use it?

A single broad review prompt mixes architecture, correctness, security, tests, performance, framework conventions, and maintainability into one context. Deep Code Review separates those concerns into isolated reviewers and merges them afterward.

Key capabilities:

- **60+ specialized review agents**
- independent parallel Codex or Claude sessions
- fresh-context synthesis
- independent confidence scoring
- holistic **P0 / P1 / P2** prioritization
- branch, uncommitted-work, and path scopes
- **NEW vs PRE-EXISTING** classification
- automatic stack-aware specialist routing for full reviews
- read-only review intent with prompt-injection and secret-handling protections
- provider-neutral execution
- Bash 3.2/macOS-compatible canonical runner

## Stack-aware reviews

The historical lightweight behavior is preserved:

- `core` is still the same small default set.
- direct aspect/reviewer IDs still work.
- `full` keeps the established cross-cutting set, then adds relevant specialists detected from changed files and project manifests.
- `smart` is an explicit alias for a stack-aware full review.

Examples of automatically detected specialists include Go, Rust, Python/Django, PHP, TypeScript frontend/backend, React, Vite, Next.js, Vue, Angular, Svelte, and React Native.

If exact historical `full` behavior is needed:

```bash
./scripts/deep-review.sh --no-auto-specialists full
```

or:

```bash
DEEP_REVIEW_AUTO_SPECIALISTS=0 ./scripts/deep-review.sh full
```

## Established review areas

| Area | Coverage |
| --- | --- |
| `core` | Essential code, silent-failure, and architecture review |
| `full` | Cross-cutting set + relevant detected stack specialists |
| `smart` | Explicit stack-aware full review alias |
| `code` | Bugs, correctness, quality, repository guidance |
| `errors` | Silent failures and error handling |
| `arch` | Dependencies, cycles, hotspots, consistency, scale |
| `types` | Type invariants and encapsulation |
| `comments` | Comment accuracy and rot |
| `tests` | Coverage quality and critical gaps |
| `simplify` | Clarity and unnecessary complexity |
| `a11y` | Accessibility / WCAG 2.2 |
| `l10n` | Localization and internationalization |
| `concurrency` | Races, deadlocks, async pitfalls |
| `perf` | Runtime and scalability bottlenecks |
| `security` | Injection, auth, access control, crypto, supply chain |
| `pii` | PII leakage and unsafe data handling |
| `review` | Repository guidelines, history, prior feedback |

## Web specialists

Deep Code Review has intentionally separate web layers:

- **TypeScript frontend (`ts-frontend`)** — browser/frontend TypeScript, TSConfig, boundaries, browser APIs, routing, generic component/state concerns.
- **TypeScript backend (`ts-backend`)** — Node/server TypeScript, runtime validation, event-loop safety, API/lifecycle concerns.
- **React (`react`)** — purity, hooks/effects, state identity, async waterfalls, React Compiler-aware performance, Suspense and recovery.
- **Vite (`vite`)** — environment exposure, dev-server security, module resolution, plugins, dependency pre-bundling, build output, assets, and SPA deployment.
- **Accessibility (`a11y`)** — semantic HTML, keyboard/focus, dynamic content, WCAG 2.2 and assistive-technology impact.

A React + Vite application may legitimately run all of `ts-frontend`, `react`, `vite`, and `a11y` because they own different failure domains.

## Language and platform reviewers

Other specialists include PHP, Python/Django, Rust, Go, Ruby/Rails, Java/Kotlin/Scala, .NET, C/C++, iOS, macOS, Android, Flutter, React Native, Next.js, Vue, Angular, Svelte, SQL, GraphQL, Docker, Kubernetes, Terraform, Shell, GitHub Actions, and agent-instruction files.

Group aliases include `ts`, `mobile`, `apple`, `jvm`, `infra`, and `containers`.

## Performance philosophy

Performance findings should follow impact order rather than micro-optimization fashion:

1. eliminate unnecessary async/network waterfalls;
2. reduce unnecessary initial bundle/module work;
3. remove expensive repeated rendering/I/O/serialization;
4. optimize hot JavaScript or allocations only with plausible measurable impact.

`perf` diagnoses bottlenecks. `optimization-reviewer` proposes benchmarkable changes. Framework/language reviewers should avoid speculative low-level tuning that belongs in those reviewers.

## Reviewer knowledge and calibration

Reviewer guidance is maintained as versioned project knowledge rather than treated as timeless style advice.

- [`REVIEWER-SOURCES.md`](REVIEWER-SOURCES.md) records the primary documentation and selected practitioner material behind reviewer rules.
- Official language/framework/specification documentation is preferred for factual claims; community guidance is used for useful patterns and failure modes.
- Reviewers should require a concrete correctness, security, accessibility, compatibility, production, or measurable performance impact before turning a best practice into a finding.
- `scripts/test-reviewer-knowledge.sh` guards high-value facts and calibration choices that are easy to regress, such as WCAG target-size levels, React Compiler-aware memoization guidance, Vite security rules, modern TypeScript options, Rust 2024 unsafe semantics, Python structured concurrency, Go concurrency tooling, and modern PHP features.

This knowledge should be periodically refreshed as frameworks, compilers, standards, and recommended practices evolve.

## Experimental production specialists

The project also contains opt-in reviewers for production failure modes:

- `optimization-reviewer`
- `api-contract-reviewer`
- `database-migration-reviewer`
- `observability-reviewer`
- `resilience-reviewer`
- `background-jobs-reviewer`
- `resource-lifecycle-reviewer`

See [`REVIEWER-COVERAGE.md`](REVIEWER-COVERAGE.md).

## How it works

1. **Scope detection** — branch diff, uncommitted work, or requested path.
2. **Stack detection** — for full/smart reviews, inspect changed files and manifests and add relevant specialists.
3. **Specialist review** — run isolated reviewers.
4. **Synthesis** — merge and deduplicate in a fresh context.
5. **Confidence scoring** — challenge findings to filter false positives.
6. **Final triage** — normalize surviving findings into P0/P1/P2; omit style-only noise.

## Safety

Repository contents are treated as **untrusted data**. Review sessions are instructed to never follow instructions embedded in source code/diffs/comments, never reproduce secrets, avoid repository modifications, and write only temporary review artifacts.

## Development

Repository contributors can exercise the compatibility wrapper directly:

```bash
./scripts/deep-review.sh --provider codex full
```

Smoke tests:

```bash
bash scripts/test-deep-review.sh
bash scripts/test-reviewer-coverage.sh
bash scripts/test-reviewer-knowledge.sh
bash scripts/test-plugin-packaging.sh
```

The canonical distributable skill lives at `skills/deep-review/`.

## Acknowledgements

This repository is a fork and evolution of Iron-Ham's `claude-deep-review`. Its reviewer architecture and specialist prompts provided the foundation for this provider-neutral Codex and Claude version.

## License

MIT — see [`LICENSE`](LICENSE).
