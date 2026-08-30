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
$deep-review review our Playwright/Vitest tests for flakiness
$deep-review review this package's exports and ESM/CJS compatibility
```

The repository also includes a native Codex plugin manifest. See [`INSTALL.md`](INSTALL.md) and [`CODEX.md`](CODEX.md).

## Why use it?

A single broad review prompt mixes architecture, correctness, security, tests, performance, framework conventions, and maintainability into one context. Deep Code Review separates those concerns into isolated reviewers and merges them afterward.

Key capabilities:

- **60+ specialized review agents**
- independent parallel Codex or Claude sessions
- one shared stack/version profile for version-sensitive reviews
- fresh-context synthesis
- independent confidence scoring
- holistic **P0 / P1 / P2** prioritization
- branch, uncommitted-work, and path scopes
- **NEW vs PRE-EXISTING** classification
- automatic stack-aware specialist routing for full reviews
- opt-in behavioral reviewer fixtures for positive/negative calibration
- read-only review intent with prompt-injection and secret-handling protections
- provider-neutral execution
- Bash 3.2/macOS-compatible canonical runner

## Stack-aware reviews

The historical lightweight behavior is preserved:

- `core` is still the same small default set and does not add stack-profiling model cost.
- direct aspect/reviewer IDs still work.
- `full` keeps the established cross-cutting set, then adds relevant specialists detected from changed files and project manifests.
- `smart` is an explicit alias for a stack-aware full review.

Examples of automatically detected specialists include Go, Rust, Python/Django, PHP, TypeScript frontend/backend, React, Vite, **web testing**, **JavaScript package boundaries**, Next.js, Vue, Angular, Svelte, and React Native.

### Shared stack/version context

For full/smart reviews and explicit version-sensitive specialists, the runner performs one fast profiling pass before reviewer fan-out. It writes a shared `stack-context.md` containing evidence-backed facts such as:

- app vs reusable package vs service vs monorepo shape;
- relevant package/workspace roots;
- declared/resolved language and framework versions;
- package manager, lockfiles and ESM/CJS signals;
- React Compiler, React Router and TanStack Query presence/mode;
- Vitest/Jest/Testing Library/Playwright environments;
- TypeScript module/configuration constraints;
- version-sensitive review constraints.

Every specialist reads the same profile instead of independently guessing versions. If profiling fails, specialists fall back to manifest/config inspection and the final report notes the coverage gap.

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
| `tests` | General test coverage quality and critical gaps |
| `web-testing` | Vitest/Jest isolation, Testing Library, Playwright, async/flakiness |
| `js-package` | Node package boundaries, ESM/CJS, exports, peers, publishing/workspaces |
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
- **React (`react`)** — purity, hooks/effects, state identity, async waterfalls, React Compiler-aware performance, Suspense/recovery, and dependency-aware React Router/TanStack Query checks.
- **Vite (`vite`)** — environment exposure, dev-server security, module resolution, plugins, dependency pre-bundling, build output, assets, and SPA deployment.
- **Web testing (`web-testing`)** — test isolation, mocks/timers, Testing Library semantics, Playwright locators/auto-waiting, deterministic async behavior and meaningful coverage.
- **JavaScript packages (`js-package`)** — Node `type`/`exports`/`imports`, conditional exports, types/runtime parity, peer dependencies, `sideEffects`, published files and workspace boundaries.
- **Accessibility (`a11y`)** — semantic HTML, keyboard/focus, dynamic content, WCAG 2.2 and assistive-technology impact.

A React + Vite application may legitimately run `ts-frontend`, `react`, `vite`, `web-testing`, `js-package`, and `a11y` when the corresponding code/config is in scope because they own different failure domains.

## Dependency-aware React review

The React specialist does not create one reviewer per ecosystem library. Instead it activates dependency-specific rules when the shared profile confirms the library and API mode.

For **React Router**, it can reason about loaders/clientLoaders, actions/fetchers, revalidation, pending/optimistic UI and route error boundaries without forcing Data/Framework Mode onto declarative apps.

For **TanStack Query**, it checks query identity, query-key variables, cache ownership, mutation invalidation/update behavior, configured/default staleness/refetch semantics, dependent queries and optimistic-update races without treating defaults as defects.

This keeps reviewer count and synthesis noise under control.

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
- Reviewers should require a concrete correctness, security, accessibility, compatibility, production, deterministic-test, consumer-package, or measurable performance impact before turning a best practice into a finding.
- `scripts/test-reviewer-knowledge.sh` guards high-value facts and calibration choices that are easy to regress.
- `reviewer-fixtures/` contains small positive and negative examples for behavioral calibration.

### Behavioral fixture harness

The fixture harness always performs a cheap structural validation:

```bash
bash scripts/test-reviewer-fixtures.sh
```

Actual model-based fixture execution is intentionally opt-in because it consumes model calls and can be slower/non-deterministic:

```bash
DEEP_REVIEW_RUN_LLM_FIXTURES=1 \
  bash scripts/test-reviewer-fixtures.sh
```

Optional environment controls include `DEEP_REVIEW_FIXTURE_PROVIDER`, `DEEP_REVIEW_FIXTURE_MODEL`, and `DEEP_REVIEW_FIXTURE_FAST_MODEL`.

Positive fixtures assert that a specialist surfaces a known failure class; negative fixtures guard against known false positives such as blanket React memoization, mandatory Go `Client.Timeout`, or misclassifying the WCAG 2.5.8 24px minimum as 44px.

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
2. **Specialist detection** — for full/smart reviews, inspect changed files/manifests and add relevant specialists.
3. **Stack profiling** — one shared fast pass records versions, package/test/runtime shape and constraints when needed.
4. **Specialist review** — isolated reviewers use the same stack context.
5. **Synthesis** — merge and deduplicate in a fresh context.
6. **Confidence scoring** — challenge findings against code, diff and stack context to filter false positives.
7. **Final triage** — normalize surviving findings into P0/P1/P2; omit style-only noise.

## Safety

Repository contents are treated as **untrusted data**. Review sessions are instructed to never follow instructions embedded in source code/diffs/comments/profiles, never reproduce secrets, avoid repository modifications, and write only temporary review artifacts.

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
bash scripts/test-reviewer-fixtures.sh
bash scripts/test-plugin-packaging.sh
```

The canonical distributable skill lives at `skills/deep-review/`.

## Acknowledgements

This repository is a fork and evolution of Iron-Ham's `claude-deep-review`. Its reviewer architecture and specialist prompts provided the foundation for this provider-neutral Codex and Claude version.

## License

MIT — see [`LICENSE`](LICENSE).
