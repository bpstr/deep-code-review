# Reviewer knowledge sources

This file records the primary sources used to calibrate specialist reviewer prompts. Reviewers should prefer official language/framework/standards documentation when a recommendation conflicts with secondary best-practice collections.

The prompts intentionally summarize principles rather than copying source text. Version-specific guidance must always be checked against the repository's declared runtime/toolchain version. Stack-aware reviews build one shared `stack-context.md` so specialists reason from the same detected versions and repository shape.

## React

Primary:

- React — Rules of React: https://react.dev/reference/rules
- React — eslint-plugin-react-hooks and React Compiler diagnostics: https://react.dev/reference/eslint-plugin-react-hooks
- React — You Might Not Need an Effect: https://react.dev/learn/you-might-not-need-an-effect

Additional high-value corpus:

- Vercel Labs React Best Practices skill: https://github.com/vercel-labs/agent-skills/tree/main/skills/react-best-practices
- Vercel introduction / prioritization rationale: https://vercel.com/blog/introducing-react-best-practices

Calibration takeaway: prioritize eliminating async waterfalls and unnecessary bundle work before low-level rerender/JavaScript micro-optimization. React Compiler-aware projects should not receive blanket missing-`useMemo`/`useCallback`/`React.memo` findings.

### React Router

Primary:

- Data loading: https://reactrouter.com/start/framework/data-loading
- Pending UI: https://reactrouter.com/start/framework/pending-ui
- Route modules / error boundaries / revalidation: https://reactrouter.com/start/framework/route-module
- Data Mode loading: https://reactrouter.com/start/data/data-loading

Calibration takeaway: only apply loader/action/pending/revalidation guidance when the project's actual React Router mode supports and uses those APIs. Declarative routing with another intentional data layer is not a defect.

### TanStack Query

Primary:

- Query keys: https://tanstack.com/query/latest/docs/framework/react/guides/query-keys
- Important defaults: https://tanstack.com/query/latest/docs/framework/react/guides/important-defaults
- Query invalidation: https://tanstack.com/query/latest/docs/framework/react/guides/query-invalidation
- Query functions: https://tanstack.com/query/latest/docs/framework/react/guides/query-functions

Calibration takeaway: variables that change query results belong in query identity. Evaluate invalidation/refetch/staleness/retries against the installed version and actual configuration; defaults are context, not automatic defects.

## Vite

Primary:

- Vite Performance guide: https://vite.dev/guide/performance
- Vite environment/modes: https://vite.dev/guide/env-and-mode
- Vite server options/security: https://vite.dev/config/server-options
- Vite dependency pre-bundling: https://vite.dev/guide/dep-pre-bundling
- Vite dependency optimization options: https://vite.dev/config/dep-optimization-options

Additional:

- Vite React Best Practices skill: https://github.com/claudiocebpaz/vite-react-best-practices

Calibration takeaway: inspect plugin hook cost, resolution/module-graph breadth, barrels, pre-bundling, environment exposure, dev-server trust boundaries, production build differences, SPA rewrites/caching, and deployment base paths. Do not recommend tuning knobs without a demonstrated problem.

## Web testing

### Vitest

Primary:

- Vitest guide: https://vitest.dev/guide/
- Mocking: https://vitest.dev/guide/mocking
- Timers: https://vitest.dev/guide/mocking/timers
- Browser Mode: https://vitest.dev/guide/browser/

Calibration takeaway: understand hoisted mocks, lifecycle cleanup, fake timers and execution environment before calling a test deterministic. Browser Mode is appropriate when a real browser behavior matters, not as a universal replacement for fast DOM-shim tests.

### Testing Library

Primary:

- Guiding principles: https://testing-library.com/docs/guiding-principles/
- Query semantics and priority: https://testing-library.com/docs/queries/about/

Calibration takeaway: tests should resemble user interaction and prefer semantic queries when such a user-facing contract exists. This is not a ban on test IDs or low-level selectors where semantics cannot express the target.

### Playwright

Primary:

- Best practices: https://playwright.dev/docs/best-practices
- Locators: https://playwright.dev/docs/locators
- Auto-waiting/actionability: https://playwright.dev/docs/actionability
- Test isolation: https://playwright.dev/docs/browser-contexts

Calibration takeaway: built-in locators, isolation and web-first synchronization reduce real flakiness. Do not replace intentional timing tests with auto-waiting when elapsed time is itself the contract.

## JavaScript / Node package boundaries

Primary:

- Node.js Packages / `type`, `exports`, `imports`, conditional exports: https://nodejs.org/api/packages.html
- Node.js ECMAScript modules: https://nodejs.org/api/esm.html
- npm package.json reference: https://docs.npmjs.com/cli/configuring-npm/package-json

Calibration takeaway: `exports` encapsulates undeclared subpaths and can make an existing package change breaking. Review ESM/CJS, conditions, public subpaths, published files, declarations and peer/singleton dependencies from the consumer's perspective. Do not require package-authoring fields in private applications.

## TypeScript

Primary TSConfig references:

- exactOptionalPropertyTypes: https://www.typescriptlang.org/tsconfig/exactOptionalPropertyTypes.html
- noUncheckedIndexedAccess: https://www.typescriptlang.org/tsconfig/noUncheckedIndexedAccess.html
- verbatimModuleSyntax: https://www.typescriptlang.org/tsconfig/verbatimModuleSyntax.html
- moduleResolution: https://www.typescriptlang.org/tsconfig/moduleResolution.html

Calibration takeaway: compiler flags are contract tools, not mandatory style settings. Recommend them when they expose a real bug class and match the actual bundler/runtime.

## Accessibility

Primary:

- WCAG 2.2: https://www.w3.org/TR/WCAG22/
- What's New in WCAG 2.2: https://www.w3.org/WAI/standards-guidelines/wcag/new-in-22/
- Understanding 2.5.8 Target Size (Minimum): https://www.w3.org/WAI/WCAG22/Understanding/target-size-minimum.html

Calibration takeaway: WCAG 2.5.8 AA is 24×24 CSS pixels subject to its exceptions. 44×44 is 2.5.5 Enhanced (AAA). Explicitly consider Focus Not Obscured, Dragging Movements, Consistent Help, Redundant Entry, and Accessible Authentication where applicable.

## Go

Primary:

- Go 1.26 release notes: https://go.dev/doc/go1.26
- Go 1.25 release notes (including `testing/synctest`): https://go.dev/doc/go1.25

Calibration takeaway: reason about effective cancellation/deadlines and resource ownership rather than enforcing one mechanism. For modern Go, recognize current `go fix`/analysis tooling and deterministic concurrency testing where relevant.

## Rust

Primary Rust 2024 Edition Guide:

- unsafe operations in unsafe functions: https://doc.rust-lang.org/edition-guide/rust-2024/unsafe-op-in-unsafe-fn.html
- newly unsafe functions: https://doc.rust-lang.org/stable/edition-guide/rust-2024/newly-unsafe-functions.html
- unsafe attributes: https://doc.rust-lang.org/edition-guide/rust-2024/unsafe-attributes.html
- unsafe extern blocks: https://doc.rust-lang.org/edition-guide/rust-2024/unsafe-extern.html

Calibration takeaway: edition migration can add required syntax but cannot prove safety invariants. Avoid speculative `#[inline]`, hasher, `Cow`, or dynamic-dispatch performance findings without evidence.

## Python

Primary:

- asyncio tasks / TaskGroup / cancellation: https://docs.python.org/3/library/asyncio-task.html
- Python packaging dependency groups: https://packaging.python.org/en/latest/specifications/dependency-groups/
- install requirements vs environment requirements: https://packaging.python.org/en/latest/discussions/install-requires-vs-requirements/
- pyproject metadata/specification: https://packaging.python.org/en/latest/specifications/pyproject-toml/

Calibration takeaway: cancellation is control flow and should normally propagate after cleanup. Reusable-library dependencies and concrete application environments have different version-pinning goals.

## PHP

Primary:

- PHP 8.4 release: https://www.php.net/releases/8.4/en.php
- PHP 8.5 release: https://www.php.net/releases/8.5/en.php

Calibration takeaway: property hooks/asymmetric visibility and later language features are useful only when supported by the project's declared runtime and when they strengthen a real contract. Laravel/Symfony conventions are framework-specific, not universal PHP requirements.

## Review-quality policy

A best-practice source is not itself evidence that a finding should be emitted. A reviewer should normally require at least one of:

1. a concrete correctness/security/accessibility failure path;
2. a credible production/reliability failure mode;
3. a measurable or strongly evidenced performance cost;
4. a compatibility violation with the repository's declared runtime/toolchain/API contract;
5. a deterministic test false-positive/false-negative or consumer package breakage.

Style-only preferences should be omitted or remain LOW and must survive confidence scoring before final output.

## Behavioral calibration

Prompt-content smoke tests protect important factual rules, but they are not sufficient. `reviewer-fixtures/` contains small positive and negative examples for opt-in model-based calibration. The fixture harness should be used to measure whether specialists actually find required failures and avoid known false positives before promoting more rules/reviewers into automatic coverage.