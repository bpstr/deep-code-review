# Reviewer Coverage Audit

Deep Code Review already has broad cross-cutting, language, framework, mobile, infrastructure, and production-readiness coverage. The next quality gains should come primarily from better routing, shared version context, calibration, and regression testing rather than continuously adding generic reviewers.

## Current direction

The canonical runner distinguishes two compatibility modes:

- `core` preserves the historical lightweight reviewer set and does not add a stack-profiler model call.
- `full` preserves the established cross-cutting set and augments it with relevant specialists detected from changed files and nearby manifests.
- `--no-auto-specialists` or `DEEP_REVIEW_AUTO_SPECIALISTS=0` restores the historical exact `full` set and its previous model-call shape.
- direct aspect and reviewer IDs remain supported.

Automatic routing stays conservative: add only reviewers with a clear stack signal, then rely on synthesis/confidence scoring to remove overlap.

## Shared stack/version context

Version-sensitive reviewers should not independently guess framework/runtime versions. Stack-specific/full reviews perform one fast profiling pass that records:

- application/library/service/CLI/monorepo shape;
- relevant workspace/package roots;
- declared or resolved language/framework versions where evidence exists;
- package manager, lockfiles, ESM/CJS and package-boundary signals;
- server-TypeScript execution mode, including native Node stripping versus `tsc`/`tsx`/loaders/bundlers;
- React Compiler, React Router, TanStack Query and rendering-mode signals;
- Vite major and Vite 8 Rolldown-era configuration signals;
- Vitest/Jest major plus Testing Library/Playwright environment and mock-lifecycle configuration;
- TypeScript major/module/config constraints;
- explicit Python free-threaded support when repository evidence exists;
- explicit version-sensitive review constraints.

All specialists read the same `stack-context.md`. If profiling fails, they fall back to repository inspection and the final report records the gap. This profile is deliberately skipped for historical `core` and exact compatibility `full` reviews.

## Web-specialist boundaries

### `react-reviewer`

Owns React-specific correctness and performance concerns: Rules of React, purity, hooks/effects, state identity, async waterfalls, React Compiler-aware memoization, Suspense/recovery, React-specific accessibility mechanisms, and dependency-aware React Router/TanStack Query correctness.

It explicitly avoids blanket recommendations for `React.memo`, `useMemo`, or `useCallback`, does not force React Router Data/Framework Mode, and treats TanStack Query defaults as context rather than defects.

### `vite-reviewer`

Owns Vite-specific concerns: client environment exposure, dev-server trust boundaries, Vite/TypeScript module alignment, plugin cost, module-graph breadth, dependency optimization, build chunks/assets/base/source maps, SPA deployment and HMR.

For Vite 8+, it also understands the Rolldown migration: production builds and dependency optimization no longer run on the historical Rollup/esbuild split. Deprecated `build.rollupOptions` and `optimizeDeps.esbuildOptions` compatibility aliases are not automatically failures; reviewers look for actual translation/semantic breakage. Vite 8.1 bundled dev mode remains experimental and is never a blanket recommendation.

### `web-testing-reviewer`

Owns web-test reliability and behavioral confidence: Vitest/Jest mock/timer lifecycle, test isolation, Testing Library semantics, Playwright locators/auto-waiting, DOM-shim vs browser mismatches, and async/flakiness mechanics.

Version calibration now includes Vitest 4's changed restore semantics and Vitest 5's default `clearMocks: true`, preventing stale advice that demands explicit clearing when the installed runner already provides it.

### `js-package-reviewer`

Owns JavaScript package-consumer boundaries: Node `type`, ESM/CJS/extensions, `exports`/`imports`/conditions, declaration/runtime parity, peer/singleton dependencies, `sideEffects`, published artifacts, workspace dependencies and semver compatibility.

Modern Node native TypeScript support does not weaken those boundaries: Node intentionally does not strip TypeScript in `node_modules`, so source-TypeScript publishing still requires an explicit consumer/runtime contract.

### `ts-frontend-reviewer`

Owns frontend TypeScript compiler/runtime alignment, boundary validation, state/async contracts and browser APIs. For TypeScript 6.0+, it accounts for changed defaults and removed/deprecated legacy options instead of applying TS 5 assumptions.

### `ts-backend-reviewer`

Owns Node/server TypeScript runtime boundaries, event-loop and process lifecycle, plus execution-mode correctness. It now distinguishes native Node TypeScript stripping from full transformer/compiler paths: native Node does not type-check or honor `tsconfig` path transforms.

### `accessibility-scanner`

Remains the authority for WCAG/assistive-technology behavior. Framework/testing reviewers should avoid duplicating generic WCAG findings.

## Automatic detection targets

A stack-aware full review can currently augment with React, Vite, Next.js, Vue, Angular, Svelte, React Native, frontend/backend TypeScript, web testing, JavaScript package boundaries, Go, Rust, Python/Django, and PHP.

Manifest lookup walks from changed files toward the repository root so monorepo package signals are less dependent on the root `package.json`. Detection remains shallow and Bash 3.2 compatible; the LLM stack profiler is responsible for richer version/tooling interpretation, not reviewer selection. No selector or routing expansion was required for the September 2026 knowledge refresh.

## Modernization priorities applied

### TypeScript

Review compiler/runtime reality rather than source syntax alone. Important optional checks include `exactOptionalPropertyTypes`, `noUncheckedIndexedAccess`, `noUncheckedSideEffectImports`, `verbatimModuleSyntax`, and a `moduleResolution` mode consistent with the actual runtime/bundler. TypeScript 6.0 changed defaults and removed/deprecated legacy options; those checks are strictly version-gated.

### React

Prioritize correctness, waterfalls and bundle/loading cost before memoization. React Compiler diagnostics and current `eslint-plugin-react-hooks` rules are relevant when the project uses them. React Router loaders/actions/pending/error boundaries and TanStack Query keys/invalidation/defaults remain conditional dependency knowledge, not mandatory architecture. No new React reviewer rules were justified in this refresh.

### Vite

For Vite 8, reason about Rolldown rather than old Rollup/esbuild implementation assumptions. Compatibility aliases are calibrated as migrations rather than failures unless they break behavior. Continue to inspect plugin hook cost, resolution operations, barrels/module breadth, dependency optimization and measured profiling before proposing tuning.

### Web testing

Vitest mock lifecycle is version-sensitive. Vitest 5 defaults `clearMocks` on; Vitest 4 changed `vi.restoreAllMocks` behavior. Testing Library and Playwright guidance remains user-facing/semantic and synchronization-focused rather than selector-style dogma.

### Node / packages

Native Node TypeScript stripping is now stable in modern Node lines, but it ignores `tsconfig` transformations and performs no typechecking. Runtime reviewers identify this execution mode before interpreting aliases/imports; package reviewers continue to enforce real consumer packaging boundaries because Node does not strip TypeScript in `node_modules`.

### Accessibility

WCAG 2.2 calibration remains correct: 2.5.8 Target Size (Minimum), AA is 24×24 CSS px subject to exceptions; 44×44 is 2.5.5 Enhanced (AAA). Existing Focus Not Obscured, Dragging Movements, Consistent Help, Redundant Entry and Accessible Authentication coverage remains current.

### Go

Go 1.27 adds generic methods and `testing/synctest.Sleep`. Reviewers must check `go.mod`/toolchain version before rejecting new syntax or recommending newer APIs. Effective cancellation/resource reasoning remains preferable to mandating one timeout mechanism.

### Rust

Rust 1.98 is current during this refresh; the existing Rust 2024 unsafe/soundness coverage remains valid. Continue to review against MSRV/edition and avoid speculative `#[inline]`, hasher, `Cow`, or generics-vs-dynamic-dispatch performance findings without evidence.

### Python

Python 3.14 officially supports free-threaded CPython. The Python reviewer only activates no-GIL-specific thread/extension checks when the repository explicitly supports/tests that runtime mode; `requires-python >=3.14` alone is not evidence. Existing cancellation/TaskGroup and package-policy calibration remains valid.

### PHP

PHP 8.4/8.5 guidance remains current for stable production lines. PHP 8.6 is still a pre-release testing line in the September 2026 refresh, so preview-only behavior must not be applied unless a project explicitly targets it.

## Reviewer quality policy

A reviewer should emit a finding only when it can explain at least one of:

1. a concrete correctness/security/accessibility failure;
2. a credible production/reliability failure mode;
3. a measurable or strongly evidenced performance cost;
4. a compatibility violation with declared runtime/toolchain/API constraints;
5. a deterministic test false-positive/false-negative or consumer-package breakage.

A pattern appearing in a best-practice guide is not sufficient by itself.

## Executable behavioral fixtures

`reviewer-fixtures/` turns selected positive and negative scenarios into an opt-in model-based evaluation harness. Static validation always checks fixture metadata/directories/reviewer IDs; model execution only runs when `DEEP_REVIEW_RUN_LLM_FIXTURES=1` is explicitly enabled.

Calibration includes React prop mutation and Compiler memoization, Vite client secrets, Playwright fixed waits, package subpath exports, TanStack Query identity, Go context timeout calibration, WCAG target sizing, test false-green/reachability cases, native Node TypeScript ignoring `tsconfig` paths, and Vitest 5's default mock-history clearing.

These behavioral fixtures complement—not replace—the cheap prompt/routing/factual smoke tests. They are expected to have some model variance, so they should inform calibration trends rather than become a mandatory install gate.

## Experimental production reviewers

These remain opt-in until they repeatedly find unique issues at an acceptable noise/token cost:

- `optimization-reviewer`;
- `api-contract-reviewer`;
- `database-migration-reviewer`;
- `observability-reviewer`;
- `resilience-reviewer`;
- `background-jobs-reviewer`;
- `resource-lifecycle-reviewer`.

Potential future areas still worth validating include cache correctness, multi-tenancy isolation, feature-flag lifecycle, time/date correctness, financial/numerical correctness, search/index consistency, data retention, and CLI contracts.

## Promotion criteria

Promote or auto-route a reviewer more aggressively when it finds issues missed by existing reviewers, findings survive confidence scoring, positive/negative fixtures show useful discrimination, overlap/noise is controlled, representative repositories validate it, and runtime/token cost is justified by issue severity.

See [`REVIEWER-SOURCES.md`](REVIEWER-SOURCES.md) for the knowledge sources behind the current calibration.