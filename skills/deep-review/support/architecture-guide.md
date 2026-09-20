# Evidence-backed architecture review

`arch` reviews dependencies, cycles, coupling, decision fit, structural change cost,
harmful duplication, unnecessary abstraction, and invariant ownership. It runs the
five established architecture reviewers plus `code-simplifier` and
`type-design-analyzer`. One shared fast stack/architecture pass supplies relevant
ADRs, declared boundaries, ownership, deployment constraints and intentional
exceptions; it does not invent requirements or prescribe a universal architecture.

`core` retains its historical seven reviewers and no profiling call. Exact
compatibility `full` (`--no-auto-specialists full`) retains its reviewer set/call
shape. Full/smart and explicit arch overlap without launching duplicate reviewers.
Direct reviewer IDs remain supported. An explicit `arch` still profiles when
automatic specialist routing is disabled.

## Usage

Run these from the repository being reviewed (using the installed skill's runner
path or a separate checkout of Deep Code Review):

```bash
# Branch changes and relevant dependency/caller boundaries
bash "$SKILL_DIR/scripts/deep-review.sh" arch

# Whole-repository architecture audit, not merely the current diff
bash "$SKILL_DIR/scripts/deep-review.sh" . arch

# Uncommitted architecture changes, with explicit framework/language knowledge
bash "$SKILL_DIR/scripts/deep-review.sh" --changes arch php
```

Reviewers may search outside a narrow scope to verify a duplicate or dependency,
but must connect each finding to the requested change. A repository-wide audit
must be requested with `.`; the presence of a scanner does not silently widen the
review into an unrelated redesign.

## What constitutes a finding

The shared [architecture contract](architecture-review.md)
requires all relevant source locations, intended constraints, observed evidence,
impact, the smallest compatible alternative, its trade-offs and validation.

Exact/renamed/near-miss code and semantic policy duplication are compared using
their invariants, side effects, owners and reasons to change. Independent policies,
generated code, migration snapshots and readable test setup need not be unified.
A large file, high fan-in, a DTO without methods or an interface used to break a
cycle is not a defect by itself. Reviewers must also consider retaining the design.

Consistency alone does not validate a bad decision. Reviewers assess actual fit:
for example a queue boundary that cannot uphold promised atomic success, manual
policy synchronization, or unnecessary indirection that amplifies a real change.
They must not invent traffic, growth, deadlines, team conflicts or future needs.

Confidence is certainty of the issue and claimed impact; severity is urgency and
magnitude. Confirmed maintainability debt can have high confidence and remain P2.
The synthesis, extraction, scoring and finalization contracts preserve that
finding and its evidence without manufacturing an immediate runtime failure.
Style-only and hypothetical redesign advice is still noise. Pre-existing P2 debt
must not automatically block an unrelated merge.

## Optional scanner evidence

Normal reviews do not invoke scanners, install packages or require Python.
Scanner integration uses Python 3's standard library on POSIX systems only.

### Execute configured project-local scanners

```bash
# Explicit consent to trust the reviewed project's binaries and configuration
bash "$SKILL_DIR/scripts/deep-review.sh" --architecture-tools . arch
```

Execution is **not sandboxed**. JavaScript/PHP configuration, autoloaders, plugins
and even local executable wrappers may execute arbitrary code or access networks.
Use this only in a trusted, appropriately isolated checkout. A generic request for
an architecture review is not consent to run project scanners. Review agents are
instructed not to install, execute or retry scanners themselves.

The adapter looks for existing project-local tools and recognized configurations:

| Tool | Executable (package root, then repository root) | Recognized configuration |
|---|---|---|
| jscpd | `node_modules/.bin/jscpd` | `.jscpd.json`, `.config/jscpd.json` |
| dependency-cruiser | `node_modules/.bin/depcruise` | `.dependency-cruiser.cjs`, `.js`, `.mjs`, `.json` |
| Deptrac | `vendor/bin/deptrac` | `deptrac.yaml`, `deptrac.yml`, `deptrac.php` |
| Semgrep | `.venv/bin/semgrep` | `.semgrep.yml`, `.semgrep.yaml` |

No PATH fallback, `npx`, package installation, arbitrary shell commands, fixer
flags, or Semgrep registry auto-configuration are used. Semgrep metrics/version
checks are explicitly disabled and Deptrac caching is disabled. Other behavior
of trusted configuration remains the tool's responsibility, not a sandbox promise.

Discovery follows selected paths and their ancestors. It does not recursively
scan all nested workspace configurations for `.`; narrow to a package or import a
project-wide report for nonstandard layouts/configuration. Configured project
roots are scanned to find cross-file candidates, then candidate locations are
filtered to intersect review scope. Both locations of a relevant clone remain.
Common vendor/build paths are filtered; project-specific exclusions/baselines are
still authoritative and limit coverage.

Branch-mode execution requires a clean worktree (including untracked files), so
working-tree results are not incorrectly attributed to committed HEAD. Use
`--changes` or path scope for dirty worktrees. Scanner execution always refreshes
provider checkpoints; it is deliberately not reused across resumed runs.

Each scanner invocation has a 45-second execution timeout, version probing has a
10-second maximum, output is bounded to 8 MiB and at most 50 candidates per tool
are retained. The collector limits discovery to 32 ancestor roots and execution
work to 16 entries; overflow is an explicit coverage gap. Child process groups are
terminated on timeout, cancellation and parent completion. Unsupported versions
or output schemas produce gaps, not an invented clean result.

### Import existing reports without execution

For global tool installations, custom configs, CI-generated reports or untrusted
checkouts, produce reports in your own trusted environment and import them:

```bash
bash "$SKILL_DIR/scripts/deep-review.sh" \
  --architecture-evidence=/secure/scanner-reports . arch
```

Recognized filenames are `jscpd-report.json`, `dependency-cruiser.json`,
`deptrac.json`, and `semgrep.json`. Paths in imported reports must resolve to files
in the current repository (relative paths are repository-relative). Outside-root
paths/symlinks are rejected. Imported freshness is always marked unverified;
reviewers must check source before relying on a candidate. Raw report digests
participate in cache invalidation, even when candidate coordinates are unchanged.

### Evidence and privacy

`architecture-evidence.json` contains tool/version/config provenance, statuses,
report digests and source coordinates, not copied source snippets or free-form
scanner messages. Original output is temporary and discarded. Treat the normalized
file as untrusted, potentially proprietary data too; do not publish it implicitly.
A tool match is only an investigation candidate. Scope exclusions, parsing errors,
missing binaries, timeouts, unsupported output, truncation and imported freshness
are surfaced in the final persisted report as well as stdout.

## Regression and behavioral calibration

```bash
# No model calls or installed scanner dependencies
python3 -m unittest discover -s scripts -p 'test_architecture_*.py' -v
bash scripts/test-architecture-fixtures.sh

# Opt-in evaluation of the FULL arch profile through normal confidence filtering
DEEP_REVIEW_RUN_LLM_FIXTURES=1 bash scripts/test-architecture-fixtures.sh
```

The deterministic suite uses fake providers/tools to verify routing, call shape,
parsing, redaction-by-omission, scope, process cleanup, cache invalidation and
report propagation. These tests do not claim to measure LLM judgment quality.

Eight separate positive/negative fixtures exercise the real `arch` pipeline at
confidence threshold 80, including a P2 duplication case, intentional similarity,
forbidden layering, valid dependency inversion, stable shared foundations, a real
startup cycle, atomicity-contract mismatch, and a legitimate validated DTO.
Regex checks are calibration signals, not proof of semantic precision; evaluate
misses and repeat runs before promoting stricter rules. Expensive evaluations are
not enabled in ordinary CI. The new CI job tests Linux and macOS with no models.

## Primary tool references

- jscpd configuration and JSON reports: https://github.com/kucherenko/jscpd
- dependency-cruiser CLI and output: https://github.com/sverweij/dependency-cruiser/blob/main/doc/cli.md
- Deptrac JSON formatter: https://deptrac.github.io/deptrac/formatters/#json-formatter
- Semgrep CLI: https://docs.semgrep.dev/cli-reference
