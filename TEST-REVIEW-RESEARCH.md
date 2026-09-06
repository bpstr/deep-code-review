# Deep research: reviewing software tests for trustworthiness

This note records the research basis for Deep Code Review's test-review rules. The goal is not to build a static "test smell" linter. The goal is to review whether tests are credible evidence that production behavior is correct.

## Executive conclusion

A useful test review should answer four questions before worrying about style or coverage:

1. **Would a plausible broken implementation make this test fail?**
2. **Does the scenario correspond to a production/public/defensive contract, or only to an invented test-only state?**
3. **Does the test exercise dependencies and environments with enough fidelity to prove the claimed behavior?**
4. **Will the test produce the same trustworthy signal across order, parallelism, time, machines and refactoring?**

This leads to a test-review model centered on false-green risk, scenario reachability, fidelity, determinism and behavioral coverage rather than raw coverage percentages or syntax-level smells.

## 1. Fault sensitivity matters more than execution coverage

Line/branch coverage proves that code executed; it does not prove that the test would notice an incorrect result. A test can execute every relevant line while asserting nothing useful, asserting only a default value, or deriving the expected value from the same broken logic as production.

Mutation testing is useful evidence here because it asks a stronger question: do tests detect small artificial defects? Large-scale Google research over roughly 15 million mutants found that developers exposed to mutation testing strengthened their suites and that mutants were coupled with real faults. An ICSE empirical study comparing testing criteria also found strong mutation testing had the highest fault revelation of the evaluated criteria.

Reviewer implication: perform a cheap **mental mutation check** even when mutation tooling is absent. Ask whether the test would fail if the changed branch were inverted, an argument ignored/swapped, a side effect skipped, a wrong ID used, an error swallowed, or a default value returned.

Sources:
- Google Research, *Long Term Effects of Mutation Testing*: https://research.google/pubs/long-term-effects-of-mutation-testing/
- ICSE 2017, *An Empirical Study on Mutation, Statement and Branch Coverage Fault Revelation...*: https://discovery.ucl.ac.uk/id/eprint/10058915/

## 2. Test values can accidentally make broken code look correct

Google's 2026 guidance demonstrates a particularly important false-green class: a broken insert implementation that ignores a value can still pass when the test expects the type's default value. Similar traps occur with empty strings, zero, false, first enum values, identical IDs, identical arguments, and homogeneous fixtures.

Reviewer implication: test data should be **discriminating**, not merely realistic-looking. Prefer values that make swapped/reused/ignored inputs observable. Use exact boundary values around transitions where appropriate. Do not mechanically ban defaults: a default is correct when the default itself is the behavior being tested.

Source:
- Google Testing Blog, *Choosing Values for Robust Tests* (2026): https://testing.googleblog.com/2026/06/choosing-values-for-robust-tests.html

## 3. Review behavior, not implementation copies

Software Engineering at Google recommends tests through public APIs, testing state rather than internal interactions, testing behaviors rather than methods, and keeping tests complete/concise. Google's "change-detector" guidance shows the pathological case: a test derived mechanically from the implementation can fail on harmless refactoring while being no better at distinguishing correct from incorrect behavior.

Common forms:
- expected values computed with the same helper/algorithm as production;
- exact private-method/internal-state assertions;
- every internal collaborator call and order verified when order is not contractual;
- broad snapshots that mostly encode incidental structure;
- assertions on SQL/log/DOM/class-name details that are not external contracts.

Reviewer implication: identify the external contract first. Internal details are valid targets only when they really are consumer/wire/protocol/observable contracts.

Sources:
- Software Engineering at Google, Unit Testing: https://abseil.io/resources/swe-book/html/ch12.html
- Google Testing Blog, *Change-Detector Tests Considered Harmful*: https://testing.googleblog.com/2015/01/testing-on-toilet-change-detector-tests.html

## 4. Realism is a contract question, not "could a normal user do this?"

"This never happens" is an unsafe test-review heuristic. A normal UI might never produce malformed JSON, corrupt queue messages, unknown enum values, old-client payloads or hostile strings, but a public/parser/security boundary may still be required to handle them. Defensive tests can also intentionally check invariant violations or corrupted persisted state.

The useful distinction is:
- **production-reachable** — normal product/system flow can create it;
- **boundary-reachable** — a public/external boundary can receive it even if first-party UI does not create it;
- **defensive** — deliberately tests a promised rejection/recovery invariant;
- **artificial-only** — possible only because the test bypasses all real validation/constraints or programs a mock to violate the real collaborator contract, with no defensive contract to justify it.

Reviewer implication: flag artificial-only scenarios when they create false confidence or maintenance cost, but protect adversarial boundary tests from false-positive "unrealistic" findings.

## 5. Test doubles trade isolation for fidelity

Software Engineering at Google's test-double guidance explicitly treats fidelity as a core property. It recommends real implementations where practical, fakes when real implementations are unsuitable, and mocks more selectively. Google's experience with widespread mocking found many tests became expensive to maintain while rarely finding bugs.

A particularly dangerous test is one where mocks define a world production cannot enter: impossible response shapes, impossible state transitions, omitted serialization/validation/transaction rules, or both sides of an API contract stubbed consistently but incorrectly.

Reviewer implication:
- trace mock/fake behavior back to the real contract;
- ask which important semantics disappear when using the double;
- look for contract tests for maintained fakes;
- do not ban mocks—timeouts, failures and expensive/nondeterministic services are legitimate uses;
- prefer state/result assertions over broad interaction choreography when the interaction is not itself the contract.

Sources:
- Software Engineering at Google, Test Doubles: https://abseil.io/resources/swe-book/html/ch13.html
- Google Testing Blog, *Increase Test Fidelity By Avoiding Mocks*: https://testing.googleblog.com/2024/02/increase-test-fidelity-by-avoiding.html

## 6. Test code should be easy enough to manually verify

Google's testing guidance emphasizes hermetic, obvious tests and notes that tests themselves generally do not have tests. Separate Google guidance recommends DAMP over aggressive DRY and warns that loops, conditionals and computed expected values can introduce bugs into test logic.

This must be calibrated rather than applied syntactically. Go's official table-driven testing guidance is an excellent counterexample to a simplistic "loops in tests are bad" rule: a loop is clear and powerful when every table entry is a complete test case with explicit inputs, expected output and a descriptive name.

Reviewer implication: flag abstraction only when it hides a behaviorally relevant value, expected result, side effect, or case. Do not report parameterization/table tests merely because they use a loop.

Sources:
- Software Engineering at Google, Testing Overview: https://abseil.io/resources/swe-book/html/ch11.html
- Google Testing Blog, *Don't Put Logic in Tests*: https://testing.googleblog.com/2014/07/testing-on-toilet-dont-put-logic-in.html
- Google Testing Blog, *Tests Too DRY? Make Them DAMP!*: https://testing.googleblog.com/2019/12/testing-on-toilet-tests-too-dry-make.html
- Go Wiki, *TableDrivenTests*: https://go.dev/wiki/TableDrivenTests

## 7. Determinism and isolation are part of correctness

Hermeticity, independence and controlled state are recurring themes in first-party testing guidance. Flaky tests make regression results unreliable; Google's empirical work studied root causes across 428 projects and starts from the premise that regression tests are expected to be deterministic for unchanged code/configuration.

Reviewer targets include:
- shared mutable globals/fixtures/database records;
- execution-order assumptions;
- collisions under parallel execution;
- real network/services in a suite intended to be hermetic;
- wall-clock sleeps instead of synchronization/controlled time;
- uncontrolled timezone/locale/DST/randomness;
- leaked timers/tasks/goroutines/resources;
- retries that hide the root cause instead of isolating a known infrastructure fault.

Sources:
- Software Engineering at Google, Testing Overview: https://abseil.io/resources/swe-book/html/ch11.html
- Google Research, *De-Flake Your Tests*: https://research.google/pubs/de-flake-your-tests-automatically-locating-root-causes-of-flaky-tests-in-code-at-google/

## 8. Automated "test smell" labels need strong calibration

The 2022 *Test Smells 20 Years Later* empirical study is an important warning for an AI reviewer. It found a substantial mismatch between common static smell definitions/detectors and real semantic or maintainability concerns; an older detector misclassified more than 70% of smell cases in the evaluated setting. Some commonly reported smells were ubiquitous in mature developer tests yet rarely represented real defects.

Reviewer implication: **never emit a finding because a smell name matches**. A loop, multiple assertions, fixture, mock, eager test, mystery guest, snapshot or helper must have a concrete false-green, false-red, fidelity, determinism or maintenance failure mode.

Source:
- Panichella et al., *Test smells 20 years later: detectability, validity, and reliability*: https://link.springer.com/article/10.1007/s10664-022-10207-5

## 9. Framework-specific evidence worth applying

### Browser / web
- Playwright: test user-visible behavior and isolate tests; locators/auto-waiting reduce timing races. https://playwright.dev/docs/best-practices
- Testing Library: tests should resemble how software is used and avoid component internals when user-observable behavior exists. https://testing-library.com/docs/guiding-principles/

### PHP / PHPUnit
- PHPUnit can report "risky" tests including tests that perform no assertion/expectation, along with other lifecycle/coverage-signal problems. https://docs.phpunit.de/en/13.4/risky-tests.html

### Python / pytest
- Fixtures are intended to provide defined, reliable, consistent context. https://docs.pytest.org/en/stable/explanation/fixtures.html
- Parametrized values are passed as-is, so mutable values changed by one invocation can affect later invocations. https://docs.pytest.org/en/stable/how-to/parametrize.html

### Go
- Table-driven tests are appropriate when each entry is a complete readable case. https://go.dev/wiki/TableDrivenTests
- Native fuzzing can find edge cases humans miss for broad input domains. https://go.dev/doc/security/fuzz/

### Java / JUnit
- JUnit Jupiter defaults to a fresh test instance per method to support isolation; `PER_CLASS` changes shared-state semantics. https://junit.org/junit5/docs/5.10.3/user-guide/index.html

### .NET
- Microsoft's current unit-testing guidance emphasizes behavioral clarity and Arrange/Act/Assert. https://learn.microsoft.com/en-us/dotnet/core/testing/unit-testing-best-practices
- MSTest guidance recommends independent tests, careful parallelization and fixing flakiness rather than relying on retries. https://learn.microsoft.com/en-us/dotnet/core/testing/unit-testing-mstest-writing-tests-controlling-execution

## 10. Review taxonomy implemented in Deep Code Review

The `test-analyzer` reviewer now evaluates existing tests and missing coverage across these categories:

- **Oracle / false-green risk** — would a plausible defect survive?
- **Scenario reachability** — is the test proving a real public/production/defensive contract?
- **Test data** — do chosen values discriminate correct from broken behavior?
- **Doubles & fidelity** — do mocks/fakes preserve the semantics being claimed?
- **Change detector** — is the test copied from implementation rather than behavior?
- **Abstraction** — can a reviewer see the important inputs and expected result?
- **Isolation & determinism** — can order/time/randomness/state/external systems lie?
- **Discovery & execution** — is the test actually run in the relevant suite/CI path?
- **Coverage & layering** — is important changed behavior tested at a layer that can observe the defect?
- **Framework semantics** — apply evidence-backed PHPUnit/pytest/Go/JUnit/.NET/web rules when detected.

## 11. Deliberate false-positive guards

The reviewer should **not** report:
- arbitrary numeric coverage targets;
- every mock, loop, fixture, helper, snapshot or parameterized test;
- rare/malformed public inputs simply because the first-party UI does not create them;
- lack of E2E coverage when a cheaper layer proves the contract;
- lack of property/fuzz/mutation testing as a default;
- theoretical flakiness without a nondeterministic dependency;
- style-only preferences that cannot explain how the test can lie or become misleading.

This calibration is as important as detection breadth. A test reviewer that produces generic smell warnings will quickly lose trust and become less useful than the tests it reviews.
