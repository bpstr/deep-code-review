# Review targets and output storage

Review results belong to Deep Code Review, not to Codex, Claude, or Copilot.
Local runs without output overrides export reports to `<resolved-root>/.deep-review/`:

```text
.deep-review/
  latest.md
  run-<fingerprint>-<timestamp>-<pid>.md
```

Each run prints its unique result path. `latest.md` is an atomically replaced
convenience copy, not a stable handle for concurrent runs. CI exports also include
JSON when `--results-dir` is explicitly set. The runner never chooses `.codex`
or another provider configuration directory for default reports.

## Resolve the target, not the caller's repository

An existing positional path or `--target PATH` selects the review target. Resolve
relative paths from the directory where the command was invoked, before changing
directories. The resolved target owns the review root, execution context, saved-run
namespace and default export location.

| Invocation/target | Resolved root | Default local reports |
| --- | --- | --- |
| `/projects/app` is a Git working tree | `/projects/app` | `/projects/app/.deep-review/` |
| `/projects/app/src` or a file inside that Git tree | `/projects/app` | `/projects/app/.deep-review/` |
| `/scratch/example` is not in Git | `/scratch/example` | `/scratch/example/.deep-review/` |
| `/scratch/example/code.php` is not in Git | `/scratch/example` | `/scratch/example/.deep-review/` |
| No target, invoked inside Git | Current worktree's root | `<worktree-root>/.deep-review/` |
| No target and no Git | Invocation directory | `<invocation-directory>/.deep-review/` |

Git discovery starts at the target directory, or at a file target's parent, never
at an unrelated caller repository. Linked worktrees use their own working-tree
root, not the primary checkout or shared Git directory. Directory symlinks resolve
to their physical directory. The selected path remains the review scope even when
its containing Git worktree determines the root.

Without Git, the default is a path review. Explicit `--branch`, `--pr` or `--changes`
requires a Git working tree; the runner does not silently substitute a different
scope. An explicit missing/non-file/non-directory `--target` fails before a run.

```bash
# Invoked from anywhere, including an unrelated checkout:
./scripts/deep-review.sh --target /projects/app full
./scripts/deep-review.sh /projects/app/src code
./scripts/deep-review.sh --target /scratch/example security

# Select another worktree, then choose its changes or branch scope:
./scripts/deep-review.sh --target /projects/app --changes tests
./scripts/deep-review.sh --target /projects/app --branch code

# Discover saved results using the same target-root rules:
./scripts/deep-review.sh --target /projects/app --latest-result
./scripts/deep-review.sh --target /scratch/example --list-runs
```

The examples use the repository's compatibility entry point. Installed skills use
their bundled `scripts/deep-review.sh` and must forward the user's target rather
than replacing it with `.` or the skill installation directory.

## Overrides, state and CI

`--results-dir DIR` overrides `DEEP_REVIEW_RESULTS_DIR`; `--output FILE` overrides
`DEEP_REVIEW_RESULT_FILE`. Supplying either disables the automatic local export.
Supplying both explicitly still exports to both destinations. Relative output,
state and slot overrides are relative to the invocation directory, not the selected
target. Explicit old paths, including `.codex/...`, remain valid user choices; no
existing files are migrated or deleted.

Recovery stays separate in the existing provider-neutral state root selected by
`--artifacts-dir`, `DEEP_REVIEW_STATE_DIR`, XDG state or the existing HOME/CI/temp
fallbacks. The canonical durable report remains `artifacts/review.md`.
Provider-slot coordination remains machine-local. Keep custom recovery state
outside the source being reviewed, or under the excluded `.deep-review/` directory.

Recognized CI/cloud environments and explicit `--ci` do **not** automatically
export into the target. Use an explicit result directory/file or the existing CI
artifact paths. This preserves support for read-only checkouts and mounted result
volumes. On a read-only local target, use an explicit writable output destination;
no report is silently redirected into a provider directory. Recovery output remains
available if a final export fails.

## Generated files and privacy

`.deep-review/` directories are excluded from Git scope diffs and recovery
fingerprints, even when a report is accidentally tracked. Path-review instructions
also exclude these generated directories from recursive source analysis. Non-Git
recovery hashes actual source contents (including file-symlink contents), so source
edits invalidate stale checkpoints while generated reports do not.

Reports are private files (mode 0600), with a private default report directory
(mode 0700). The default `.deep-review` destination must not be a symlink. Reports
may contain proprietary source references; do not publish them implicitly.

Add `/.deep-review/` to the target repository's `.gitignore` when desired. The
review runner does not modify the user's `.gitignore`, `.git/info/exclude`, source
files, or provider installation/configuration directories to hide its outputs.
