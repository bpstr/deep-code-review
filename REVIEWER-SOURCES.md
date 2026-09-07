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

- Vite 8 announcement: https://vite.dev/blog/announcing-vite8
- Vite 8.1 announcement / experimental bundled dev mode: https://vite.dev/blog/announcing-vite8-1
- Migration from Vite 7: https://vite.dev/guide/migration
- Vite Performance guide: https://vite.dev/guide/performance
- Vite environment/modes: https://vite.dev/guide/env-and-mode
- Vite server options/security: https://vite.dev/config/server-options
- Vite dependency optimization options: https://vite.dev/config/dep-optimization-options
- Vite build options: https://vite.dev/config/build-options

Additional:

- Vite React Best Practices skill: https://github.com/claudiocebpaz/vite-react-best-practices

Calibration takeaway: Vite 8 uses Rolldown for production builds and dependency optimization. `build.rollupOptions` and `optimizeDeps.esbuildOptions` may remain compatibility aliases while being deprecated; do not call them broken solely because they are old names. Inspect actual translation/semantic differences, plugin compatibility, module-graph breadth, environment exposure, dev-server trust boundaries, production build behavior, SPA rewrites/caching, and deployment base paths. Vite 8.1 bundled dev mode is experimental and workload-specific, not a universal recommendation.

## Web testing

### Vitest

Primary:

- Vitest guide: https://vitest.dev/guide/
- Vitest 5 announcement: https://vitest.dev/blog/vitest-5
- Migration guide (including Vitest 4 and 5): https://vitest.dev/guide/migration/
- Mocking: https://vitest.dev/guide/mocking
- Timers: https://vitest.dev/guide/mocking/timers
- Browser Mode: https://vitest.dev/guide/browser/

Calibration takeaway: understand the installed major before reasoning about mock lifecycle. Vitest 4 changed `vi.restoreAllMocks` semantics; Vitest 5 defaults `clearMocks` to true, so explicit manual clearing is not universally required. Understand hoisted mocks, fake timers and execution environment before calling a test deterministic. Browser Mode is appropriate when real browser behavior matters, not as a universal replacement for fast DOM-shim tests.

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

### Jest

Primary:

- Jest 30 announcement: https://jestjs.io/blog/2025/06/04/jest-30
- Jest configuration: https://jestjs.io/docs/configuration
- Jest mock functions: https://jestjs.io/docs/mock-function-api

Calibration takeaway: Jest 30 has different supported Node/TypeScript/jsdom baselines than older majors. Keep Vitest and Jest lifecycle assumptions separate even when their APIs look similar.

## JavaScript / Node package boundaries

Primary:

- Node.js Packages / `type`, `exports`, `imports`, conditional exports: https://nodejs.org/api/packages.html
- Node.js ECMAScript modules: https://nodejs.org/api/esm.html
- Node.js native TypeScript execution/type stripping: https://nodejs.org/api/typescript.html
- npm package.json reference: https://docs.npmjs.com/cli/configuring-npm/package-json

Calibration takeaway: `exports` encapsulates undeclared subpaths and can make an existing package change breaking. Review ESM/CJS, conditions, public subpaths, published files, declarations and peer/singleton dependencies from the consumer's perspective. Modern Node native TypeScript stripping performs no type checking, ignores `tsconfig` transforms such as `paths`, requires correct type-import semantics, and intentionally refuses TypeScript stripping under `node_modules`; do not treat native `.ts` execution as proof a source-TypeScript package is consumable. Do not require package-authoring fields in private applications.

## TypeScript

Primary:

- TypeScript 6.0 release notes: https://www.typescriptlang.org/docs/handbook/release-notes/typescript-6-0.html
- exactOptionalPropertyTypes: https://www.typescriptlang.org/tsconfig/exactOptionalPropertyTypes.html
- noUncheckedIndexedAccess: https://www.typescriptlang.org/tsconfig/noUncheckedIndexedAccess.html
- noUncheckedSideEffectImports: https://www.typescriptlang.org/tsconfig/noUncheckedSideEffectImports.html
- verbatimModuleSyntax: https://www.typescriptlang.org/tsconfig/verbatimModuleSyntax.html
- moduleResolution: https://www.typescriptlang.org/tsconfig/moduleResolution.html

Calibration takeaway: compiler flags are contract tools, not mandatory style settings. TypeScript 6.0 changes several defaults and removes/deprecates legacy options, including removal of `moduleResolution: classic`/`outFile` and deprecation of `moduleResolution: node`/`node10`, `baseUrl`, ES5 target and other legacy paths. Check the installed compiler: a TS6 removal can be a compile blocker, while a deprecation or omitted default should not be misreported as a current runtime bug.

## Accessibility

Primary:

- WCAG 2.2: https://www.w3.org/TR/WCAG22/
- What's New in WCAG 2.2: https://www.w3.org/WAI/standards-guidelines/wcag/new-in-22/
- Understanding 2.5.8 Target Size (Minimum): https://www.w3.org/WAI/WCAG22/Understanding/target-size-minimum.html

Calibration takeaway: WCAG 2.5.8 AA is 24×24 CSS pixels subject to its exceptions. 44×44 is 2.5.5 Enhanced (AAA). Explicitly consider Focus Not Obscured, Dragging Movements, Consistent Help, Redundant Entry, and Accessible Authentication where applicable.

## Go

Primary:

- Go 1.27 release notes: https://go.dev/doc/go1.27
- Go 1.27 release announcement: https://go.dev/blog/go1.27
- Go 1.26 release notes: https://go.dev/doc/go1.26
- Go 1.25 release notes: https://go.dev/doc/go1.25

Calibration takeaway: reason about effective cancellation/deadlines and resource ownership rather than enforcing one mechanism. Go 1.27 adds generic methods and `testing/synctest.Sleep`; do not reject new syntax or require newer APIs without checking the module's Go version. Recognize current `go fix`/analysis tooling and deterministic concurrency testing where relevant.

## Rust

Primary:

- Current Rust release notes: https://doc.rust-lang.org/stable/releases.html
- Rust 2024 unsafe operations in unsafe functions: https://doc.rust-lang.org/edition-guide/rust-2024/unsafe-op-in-unsafe-fn.html
- Rust 2024 newly unsafe functions: https://doc.rust-lang.org/stable/edition-guide/rust-2024/newly-unsafe-functions.html
- Rust 2024 unsafe attributes: https://doc.rust-lang.org/edition-guide/rust-2024/unsafe-attributes.html
- Rust 2024 unsafe extern blocks: https://doc.rust-lang.org/edition-guide/rust-2024/unsafe-extern.html

Calibration takeaway: edition migration can add required syntax but cannot prove safety invariants. Review against the crate's MSRV and edition. Current compiler lints may expose additional correctness risks, but avoid speculative `#[inline]`, hasher, `Cow`, or dynamic-dispatch performance findings without evidence.

## Python

Primary:

- Python 3.14 release/download information: https://www.python.org/downloads/
- Python free-threading support: https://docs.python.org/3/howto/free-threading-python.html
- C API extension support for free threading: https://docs.python.org/3/howto/free-threading-extensions.html
- asyncio tasks / TaskGroup / cancellation: https://docs.python.org/3/library/asyncio-task.html
- Python packaging dependency groups: https://packaging.python.org/en/latest/specifications/dependency-groups/
- install requirements vs environment requirements: https://packaging.python.org/en/latest/discussions/install-requires-vs-requirements/
- pyproject metadata/specification: https://packaging.python.org/en/latest/specifications/pyproject-toml/

Calibration takeaway: cancellation is control flow and should normally propagate after cleanup. Reusable-library dependencies and concrete application environments have different version-pinning goals. Python 3.14 officially supports free-threaded CPython, but it remains a distinct build/runtime mode; only apply no-GIL thread-safety/extension rules when the repository explicitly supports or tests that mode.

## PHP

Primary:

- PHP 8.4 release: https://www.php.net/releases/8.4/en.php
- PHP 8.5 release: https://www.php.net/releases/8.5/en.php
- PHP release/news page: https://www.php.net/

Calibration takeaway: property hooks/asymmetric visibility and later language features are useful only when supported by the project's declared runtime and when they strengthen a real contract. Laravel/Symfony conventions are framework-specific, not universal PHP requirements. As of the September 2026 calibration, PHP 8.6 is still a pre-release testing line; do not apply preview-only 8.6 behavior to production projects unless they explicitly target it. Refresh this statement when 8.6 becomes stable.

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