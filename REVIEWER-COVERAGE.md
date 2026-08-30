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

Version-sensitive reviewers should not independently guess framework/runtime versions. Stack-specific/full reviews now perform one fast profiling pass that records:

- application/library/service/CLI/monorepo shape;
- relevant workspace/package roots;
- declared or resolved language/framework versions where evidence exists;
- package manager, lockfiles, ESM/CJS and package-boundary signals;
- React Compiler, React Router, TanStack Query and rendering-mode signals;
- Vitest/Jest/Testing Library/Playwright environment;
- TypeScript module/config constraints;
- explicit version-sensitive review constraints.

All specialists read the same `stack-context.md`. If profiling fails, they fall back to repository inspection and the final report records the gap. This profile is deliberately skipped for historical `core` and exact compatibility `full` reviews.

## Web-specialist boundaries

### `react-reviewer`

Owns React-specific correctness and performance concerns:

- Rules of React, purity and immutable snapshots;
- hooks/effects and stale synchronization;
- state/component identity and keyed remount behavior;
- async waterfalls and loading boundaries;
- React Compiler-aware memoization guidance;
- Suspense/error-boundary recovery;
- React-specific accessibility/focus mechanisms;
- dependency-aware React Router and TanStack Query correctness.

It explicitly avoids blanket recommendations for `React.memo`, `useMemo`, or `useCallback`, does not force React Router Data/Framework Mode, and treats TanStack Query defaults as context rather than defects.

### `vite-reviewer`

Owns Vite-specific concerns:

- `VITE_*`/client environment exposure;
- dev-server trust boundaries such as `allowedHosts`;
- Vite + TypeScript module-resolution alignment;
- plugin-hook startup/transform cost;
- module-graph breadth, barrels and dependency pre-bundling;
- build chunks/assets/base/source maps;
- SPA deep-link rewrites and caching;
- HMR/config stability.

It should not recommend `optimizeDeps`, warmup, manual chunks, or plugin rewrites without a demonstrated issue.

### `web-testing-reviewer`

Owns web-test reliability and behavioral confidence:

- Vitest/Jest mock and fake-timer lifecycle;
- test isolation and parallel-order safety;
- Testing Library semantic queries and async query semantics;
- Playwright locators, auto-waiting, isolation, event ordering and fixed-wait flakiness;
- DOM-shim vs real-browser environment mismatches;
- weak/implementation-detail assertions and boundary-coverage gaps.

It is auto-routed only when supported web testing dependencies are detected.

### `js-package-reviewer`

Owns JavaScript package-consumer boundaries:

- Node `type`, ESM/CJS and extensions;
- `exports`, `imports`, conditions and public subpaths;
- runtime/declaration parity;
- peer/singleton dependency correctness;
- `sideEffects` and required initialization;
- published files/build artifacts;
- monorepo hidden/undeclared dependencies;
- semver/consumer compatibility.

It is relevant to JavaScript/TypeScript package manifests but should distinguish private applications from publishable/reused packages.

### `ts-frontend-reviewer`

Concentrates on frontend TypeScript itself: TSConfig semantics, runtime trust boundaries, async/state contracts, browser APIs and generic routing/loading concerns.

### `accessibility-scanner`

Remains the authority for WCAG/assistive-technology behavior. Framework/testing reviewers should avoid duplicating generic WCAG findings.

## Automatic detection targets

A stack-aware full review can currently augment with:

- React, Vite, Next.js, Vue, Angular, Svelte, React Native;
- frontend or backend TypeScript based on changed files/manifests;
- web testing when Vitest/Jest/Testing Library/Playwright is present;
- JavaScript package-boundary review when a relevant `package.json` is present;
- Go;
- Rust;
- Python and Django;
- PHP.

Manifest lookup walks from changed files toward the repository root so monorepo package signals are less dependent on the root `package.json`. Detection remains shallow and Bash 3.2 compatible; the LLM stack profiler is responsible for richer version/tooling interpretation, not reviewer selection.

## Modernization priorities applied

### TypeScript

Review compiler/runtime reality rather than source syntax alone. Important optional checks include `exactOptionalPropertyTypes`, `noUncheckedIndexedAccess`, `verbatimModuleSyntax`, and a `moduleResolution` mode consistent with the actual runtime/bundler.

### React

Prioritize correctness, waterfalls and bundle/loading cost before memoization. React Compiler diagnostics and current `eslint-plugin-react-hooks` rules are relevant when the project uses them. React Router loaders/actions/pending/error boundaries and TanStack Query keys/invalidation/defaults are conditional dependency knowledge, not mandatory architecture.

### Vite

Use official Vite performance guidance: inspect plugin hook cost, resolution operations, barrels/module breadth, dependency pre-bundling and measured profiling before proposing tuning.

### Accessibility

Correct WCAG 2.2 target-size guidance:

- 2.5.8 Target Size (Minimum), AA: 24×24 CSS px or applicable exception.
- 2.5.5 Target Size (Enhanced), AAA: 44×44 CSS px.

Also cover 2.4.11 Focus Not Obscured, 2.5.7 Dragging Movements, 3.2.6 Consistent Help, 3.3.7 Redundant Entry, and 3.3.8 Accessible Authentication where triggered.

### Go

Prefer effective lifetime/cancellation/resource reasoning over one mandated mechanism. Recognize modern Go analysis tooling and deterministic concurrency testing where supported.

### Rust

Cover Rust 2024 unsafe changes and explicitly avoid speculative `#[inline]`, hasher, `Cow`, and generics-vs-dynamic-dispatch optimization findings without evidence.

### Python

Treat cancellation as control flow and understand `TaskGroup` structured concurrency. Distinguish abstract library dependencies from pinned/reproducible application environments.

### PHP

Stay version-aware through PHP 8.4/8.5, including property hooks and asymmetric visibility where they strengthen contracts. Distinguish generic PHP from Laravel/Symfony conventions and application vs reusable-package Composer policy.

## Reviewer quality policy

A reviewer should emit a finding only when it can explain at least one of:

1. a concrete correctness/security/accessibility failure;
2. a credible production/reliability failure mode;
3. a measurable or strongly evidenced performance cost;
4. a compatibility violation with declared runtime/toolchain/API constraints;
5. a deterministic test false-positive/false-negative or consumer-package breakage.

A pattern appearing in a best-practice guide is not sufficient by itself.

## Executable behavioral fixtures

`reviewer-fixtures/` now turns selected positive and negative scenarios into an opt-in model-based evaluation harness. Static validation always checks fixture metadata/directories/reviewer IDs; model execution only runs when `DEEP_REVIEW_RUN_LLM_FIXTURES=1` is explicitly enabled.

Initial calibration includes:

| Scenario | Expected behavior |
| --- | --- |
| React component mutates props during render | React correctness finding |
| React Compiler project without manual memoization | no blanket missing-memoization finding |
| Vite client reads a secret-shaped `VITE_*` variable | client-secret finding |
| Playwright uses `waitForTimeout` as synchronization | web-test flakiness finding |
| package self-imports a subpath excluded by `exports` | package-boundary finding |
| TanStack Query query function depends on an ID absent from `queryKey` | wrong-cache/query-identity finding |
| Go HTTP request bounded by propagated context but no `Client.Timeout` | no blanket Client.Timeout finding |
| 24×24 accessible pointer target | no WCAG 2.5.8 finding merely for not being 44×44 |

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

Promote or auto-route a reviewer more aggressively when:

1. it finds issues missed by existing reviewers;
2. findings survive confidence scoring at a useful rate;
3. positive/negative fixtures show useful discrimination;
4. overlap/noise is controlled;
5. it works across representative repositories;
6. runtime/token cost is justified by issue severity.

See [`REVIEWER-SOURCES.md`](REVIEWER-SOURCES.md) for the knowledge sources behind the current calibration.
