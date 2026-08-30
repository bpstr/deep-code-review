# Reviewer Coverage Audit

Deep Code Review already has broad cross-cutting, language, framework, mobile, infrastructure, and production-readiness coverage. The next quality gains should come primarily from better routing, calibration, and regression testing rather than continuously adding generic reviewers.

## Current direction

The canonical runner now distinguishes two modes:

- `core` preserves the historical lightweight reviewer set.
- `full` preserves the established cross-cutting set and augments it with relevant specialists detected from changed files and manifests.
- `--no-auto-specialists` or `DEEP_REVIEW_AUTO_SPECIALISTS=0` restores the historical exact `full` set.
- direct aspect and reviewer IDs remain supported.

This is intentionally conservative: automatic routing should add only reviewers with a clear stack signal, then rely on synthesis/confidence scoring to remove overlap.

## New web-specialist boundaries

### `react-reviewer`

Owns React-specific correctness and performance concerns:

- Rules of React, purity and immutable snapshots
- hooks/effects and stale synchronization
- state/component identity and keyed remount behavior
- async waterfalls and loading boundaries
- React Compiler-aware memoization guidance
- Suspense/error-boundary recovery
- React-specific accessibility/focus mechanisms

It explicitly avoids blanket recommendations for `React.memo`, `useMemo`, or `useCallback`.

### `vite-reviewer`

Owns Vite-specific concerns:

- `VITE_*`/client environment exposure
- dev-server trust boundaries such as `allowedHosts`
- Vite + TypeScript module-resolution alignment
- plugin-hook startup/transform cost
- module-graph breadth, barrels and dependency pre-bundling
- build chunks/assets/base/source maps
- SPA deep-link rewrites and caching
- HMR/config stability

It should not recommend `optimizeDeps`, warmup, manual chunks, or plugin rewrites without a demonstrated issue.

### `ts-frontend-reviewer`

Now concentrates on frontend TypeScript itself: TSConfig semantics, runtime trust boundaries, async/state contracts, browser APIs and generic routing/loading concerns.

### `accessibility-scanner`

Remains the authority for WCAG/assistive-technology behavior. Framework reviewers should avoid duplicating generic WCAG findings.

## Automatic detection targets

The full-review detector can currently augment with:

- React, Vite, Next.js, Vue, Angular, Svelte, React Native
- frontend or backend TypeScript based on changed files/manifests
- Go
- Rust
- Python and Django
- PHP

Detection should stay shallow, portable, and Bash 3.2 compatible. It is not intended to replace explicit user-selected aspects for complex monorepos.

## Modernization priorities applied

### TypeScript

Review compiler/runtime reality rather than source syntax alone. Important optional checks include `exactOptionalPropertyTypes`, `noUncheckedIndexedAccess`, `verbatimModuleSyntax`, and a `moduleResolution` mode consistent with the actual runtime/bundler.

### React

Prioritize correctness, waterfalls and bundle/loading cost before memoization. React Compiler diagnostics and current `eslint-plugin-react-hooks` rules are relevant when the project uses them.

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
4. a compatibility violation with declared runtime/toolchain/API constraints.

A pattern appearing in a best-practice guide is not sufficient by itself.

## Regression scenarios

High-value golden scenarios for future LLM-evaluated fixtures:

| Scenario | Expected behavior |
| --- | --- |
| React Compiler project without manual memoization | no missing-memoization finding |
| React component mutates props during render | React correctness finding |
| independent sequential awaits on a critical path | waterfall finding |
| Vite `VITE_DATABASE_PASSWORD` consumed by client | client-secret finding |
| Vite `server.allowedHosts: true` | dev-server security finding |
| Vite project with healthy automatic dependency discovery | no missing `optimizeDeps` finding |
| 24×24 WCAG AA pointer target | no 2.5.8 size failure solely for not being 44×44 |
| drag-only reorder control with no single-pointer alternative | 2.5.7 finding |
| Go HTTP request bounded by propagated context but no `Client.Timeout` | no blanket timeout finding |
| Rust standard HashMap on non-hot code | no hasher optimization finding |
| Python reusable library with compatible version ranges | no exact-pin requirement |
| PHP reusable library without application lockfile policy | no universal lockfile finding |

These should eventually become executable LLM evaluation fixtures. The lightweight repository tests currently verify reviewer presence, routing contracts, and key factual calibration statements.

## Experimental production reviewers

These remain opt-in until they repeatedly find unique issues at an acceptable noise/token cost:

- `optimization-reviewer`
- `api-contract-reviewer`
- `database-migration-reviewer`
- `observability-reviewer`
- `resilience-reviewer`
- `background-jobs-reviewer`
- `resource-lifecycle-reviewer`

Potential future areas still worth validating include cache correctness, multi-tenancy isolation, feature-flag lifecycle, time/date correctness, financial/numerical correctness, search/index consistency, data retention, and CLI contracts.

## Promotion criteria

Promote or auto-route a reviewer more aggressively when:

1. it finds issues missed by existing reviewers;
2. findings survive confidence scoring at a useful rate;
3. overlap/noise is controlled;
4. it works across representative repositories;
5. runtime/token cost is justified by issue severity.

See [`REVIEWER-SOURCES.md`](REVIEWER-SOURCES.md) for the knowledge sources behind the current calibration.
