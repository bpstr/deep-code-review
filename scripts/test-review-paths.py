#!/usr/bin/env python3
"""Credential-free target/storage regressions using the real runner and engine.

Only provider responses and prompt fixtures are synthetic. Git discovery, scopes,
checkpoints, fingerprints, provider shims, exports and permissions are exercised.
Run with BASH_TEST=/path/to/bash to check another Bash version (including 3.2).
"""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

SOURCE = Path(__file__).resolve().parents[1] / "skills/deep-review/scripts"
BASH = os.environ.get("BASH_TEST", "/bin/bash")
MOCK = r'''#!/usr/bin/env python3
import os
from pathlib import Path
import sys
assert Path.cwd().resolve() == Path(os.environ["EXPECT_REVIEW_ROOT"]).resolve(), "wrong review root"
a = sys.argv[1:]
prompt = a[-1] if Path(sys.argv[0]).name == "codex" else a[a.index("-p") + 1]
w = Path(os.environ["DEEP_REVIEW_ACTIVE_WORK_DIR"])
if "specialized READ-ONLY" in prompt:
    output = next(line.split(": ", 1)[1] for line in prompt.splitlines()
                  if line.startswith("Write your complete Markdown findings to: "))
    Path(output).write_text("# Mock finding\n")
elif "synthesis agent" in prompt:
    if os.environ.get("FAIL_SYNTH") == "1":
        sys.exit(9)
    (w / "REPORT.md").write_text("# Review\nroot=" + str(Path.cwd()) + "\n")
elif "extract every distinct" in prompt:
    (w / "findings/count.txt").write_text("1\n")
    (w / "findings/finding-1.md").write_text("TITLE: Mock finding\nDETAILS: fixture only\n")
elif "confidence scorer for a batch" in prompt:
    (w / "findings/score-1.txt").write_text("SCORE: 90\nREASON: fixture only\n")
elif "final code-review triage editor" in prompt:
    (w / "FINAL.md").write_bytes((w / "REPORT.md").read_bytes())
else:
    raise AssertionError("Unexpected provider stage")
'''


class ReviewPaths(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="deep-review paths ")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve()
        self.skill = self.root / "installed skill"
        scripts = self.skill / "scripts"
        scripts.mkdir(parents=True)
        for name in ("deep-review.sh", "deep-review-engine.sh", "review-paths.sh",
                     "deep-review-provider-shim.sh", "deep-review-mktemp-shim.sh", "review-cache.sh"):
            shutil.copy2(SOURCE / name, scripts / name)
        for name in ("agents/code-reviewer.md", "agents/synthesizer.md",
                     "support/stack-profiler.md", "support/architecture-review.md",
                     "support/architecture-context.md", "support/finding-validation.md",
                     "scripts/architecture-evidence.py", "scripts/deep-review-ci.py"):
            p = self.skill / name
            p.parent.mkdir(parents=True, exist_ok=True)
            p.write_text("# Test-only prompt fixture; no scanners or CI validation executed.\n")
        for name in ("silent-failure-hunter", "dependency-mapper", "cycle-detector",
                     "hotspot-analyzer", "pattern-scout", "scale-assessor"):
            (self.skill / "agents" / (name + ".md")).write_text("# Mock specialist fixture\n")
        self.runner = scripts / "deep-review.sh"
        self.env = {k: v for k, v in os.environ.items()
                    if not k.startswith(("DEEP_REVIEW_", "GIT_")) and k not in {
                        "CI", "GITHUB_ACTIONS", "GITLAB_CI", "BUILDKITE", "CIRCLECI",
                        "TF_BUILD", "JENKINS_URL", "GITHUB_OUTPUT", "REVIEW_BASE",
                        "REVIEW_MODEL", "MAX_CONCURRENT", "CONFIDENCE_THRESHOLD"}}
        for name in ("bin", "state", "slots", "home", "tmp", "caller", "plain"):
            (self.root / name).mkdir()
        for provider in ("codex", "claude", "copilot"):
            p = self.root / "bin" / provider
            p.write_text(MOCK)
            p.chmod(0o755)
        self.env.update(PATH=str(self.root / "bin") + os.pathsep + self.env["PATH"],
                        HOME=str(self.root / "home"), TMPDIR=str(self.root / "tmp"),
                        DEEP_REVIEW_STATE_DIR=str(self.root / "state"),
                        DEEP_REVIEW_SLOT_DIR=str(self.root / "slots"),
                        DEEP_REVIEW_MEMORY_RESERVE_MB="0",
                        DEEP_REVIEW_PROVIDER_TIMEOUT_SECONDS="10")
        self.caller = self.root / "caller"
        self.plain = self.root / "plain"
        (self.plain / "source.txt").write_text("plain source\n")
        self.repo = self.root / "target repo"
        self.repo.mkdir()
        self.git(self.repo, "init", "-q")
        self.git(self.repo, "symbolic-ref", "HEAD", "refs/heads/main")
        (self.repo / "src").mkdir()
        (self.repo / "src/source.txt").write_text("base source\n")
        (self.repo / ".gitignore").write_text("# keep user configuration unchanged\n")
        self.git(self.repo, "add", ".")
        self.git(self.repo, "commit", "-qm", "base")
        self.git(self.repo, "checkout", "-qb", "feature")
        (self.repo / "src/source.txt").write_text("feature source\n")
        self.git(self.repo, "add", ".")
        self.git(self.repo, "commit", "-qm", "feature")

    def git(self, cwd, *args):
        return subprocess.run(["git", "-c", "user.name=Test", "-c", "user.email=test@example.invalid",
                               "-c", "core.hooksPath=/dev/null", *args], cwd=cwd, env=self.env,
                              text=True, capture_output=True, check=True).stdout.strip()

    def invoke(self, cwd, target_root, *args, code=0, env=None):
        e = dict(self.env, EXPECT_REVIEW_ROOT=str(target_root))
        e.update(env or {})
        result = subprocess.run([BASH, str(self.runner), *map(str, args)], cwd=cwd, env=e,
                                text=True, capture_output=True, timeout=30)
        self.assertEqual(result.returncode, code, result.stdout + result.stderr)
        return result

    def review(self, cwd, target_root, *args, **kwargs):
        return self.invoke(cwd, target_root, "--provider", "codex", *args, "code", **kwargs)

    def latest(self, target):
        result = self.invoke(self.caller, target, "--latest-artifacts", "--target", target)
        return Path(result.stdout.strip())

    def assert_export(self, target_root, stdout):
        reports = target_root / ".deep-review"
        self.assertEqual((reports / "latest.md").read_text(), stdout)
        self.assertTrue(list(reports.glob("run-*.md")))
        self.assertEqual((reports / "latest.md").stat().st_mode & 0o777, 0o600)
        self.assertFalse((target_root / ".codex").exists())

    def test_external_git_target_and_relative_nested_scope(self):
        self.git(self.caller, "init", "-q")
        nested = self.caller / "nested"
        nested.mkdir()
        rel = os.path.relpath(self.repo / "src", nested)
        result = self.review(nested, self.repo, rel)
        self.assert_export(self.repo, result.stdout)
        self.assertFalse((self.caller / ".deep-review").exists())
        self.assertFalse((self.repo / "src/.deep-review").exists())
        artifacts = self.latest(self.repo)
        self.assertEqual((artifacts / "changed-files.txt").read_text(), "src\n")
        self.assertIn("Generated .deep-review/ directories are excluded", (artifacts / "scope.txt").read_text())
        self.assertEqual((self.repo / ".gitignore").read_text(), "# keep user configuration unchanged\n")
        saved = self.invoke(nested, self.repo, "--latest-result", rel).stdout.strip()
        self.assertEqual(Path(saved).read_text(), result.stdout)

    def test_implicit_git_root_from_nested_cwd(self):
        result = self.review(self.repo / "src", self.repo)
        self.assert_export(self.repo, result.stdout)
        self.assertEqual((self.latest(self.repo) / "changed-files.txt").read_text(), "src/source.txt\n")

    def test_non_git_directory_and_implicit_cwd(self):
        self.git(self.caller, "init", "-q")
        result = self.review(self.caller, self.plain, "--target", self.plain)
        self.assert_export(self.plain, result.stdout)
        result = self.review(self.plain, self.plain)
        self.assert_export(self.plain, result.stdout)
        self.assertFalse((self.caller / ".deep-review").exists())

    def test_no_arguments_without_git(self):
        result = self.invoke(self.plain, self.plain)
        self.assert_export(self.plain, result.stdout)
        self.assertEqual((self.latest(self.plain) / "changed-files.txt").read_text(), ".\n")

    def test_file_targets_in_git_and_without_git(self):
        for target, expected in ((self.repo / "src/source.txt", self.repo),
                                 (self.plain / "source.txt", self.plain)):
            with self.subTest(target=target):
                result = self.review(self.caller, expected, target)
                self.assert_export(expected, result.stdout)
                self.assertIn(target.name, (self.latest(expected) / "changed-files.txt").read_text())

    def test_explicit_modes_require_git_and_missing_targets_fail(self):
        for mode in ("--changes", "--branch"):
            result = self.review(self.caller, self.plain, "--target", self.plain, mode, code=2)
            self.assertIn("requires a Git working tree", result.stderr)
        self.review(self.caller, self.plain, "--target", self.plain / "missing", code=2)
        self.assertFalse((self.plain / ".deep-review").exists())
        self.assertFalse((self.root / "state/repos").exists())

    def test_provider_neutral_default(self):
        for provider in ("codex", "claude", "copilot"):
            with self.subTest(provider=provider):
                result = self.invoke(self.caller, self.plain, "--provider", provider, self.plain, "code")
                self.assert_export(self.plain, result.stdout)
        self.assertEqual(len(list((self.plain / ".deep-review").glob("run-*.md"))), 3)

    def test_output_overrides_remain_relative_to_caller(self):
        result = self.review(self.caller, self.plain, self.plain,
                             "--output", "chosen/report.md", "--results-dir", "chosen/reports",
                             env={"DEEP_REVIEW_RESULT_FILE": "wrong.md",
                                  "DEEP_REVIEW_RESULTS_DIR": "wrong-results",
                                  "DEEP_REVIEW_STATE_DIR": "relative-state"})
        self.assertEqual((self.caller / "chosen/report.md").read_text(), result.stdout)
        self.assertEqual((self.caller / "chosen/reports/latest.md").read_text(), result.stdout)
        self.assertTrue((self.caller / "relative-state/repos").is_dir())
        self.assertFalse((self.caller / "wrong.md").exists())
        self.assertFalse((self.caller / "wrong-results").exists())
        self.assertFalse((self.plain / ".deep-review").exists())

    def test_environment_output_overrides_and_output_only(self):
        result = self.review(self.caller, self.plain, self.plain,
                             env={"DEEP_REVIEW_RESULT_FILE": "env-report.md"})
        self.assertEqual((self.caller / "env-report.md").read_text(), result.stdout)
        self.assertFalse((self.plain / ".deep-review").exists())
        result = self.review(self.caller, self.plain, self.plain,
                             env={"DEEP_REVIEW_RESULTS_DIR": "env-reports"})
        self.assertEqual((self.caller / "env-reports/latest.md").read_text(), result.stdout)
        self.assertFalse((self.plain / ".deep-review").exists())

    def test_ci_environment_does_not_export_into_target_by_default(self):
        result = self.review(self.caller, self.plain, self.plain, env={"CI": "true"})
        self.assertFalse((self.plain / ".deep-review").exists())
        self.assertEqual((self.latest(self.plain) / "review.md").read_text(), result.stdout)
        result = self.review(self.caller, self.plain, self.plain, "--results-dir", "ci-reports",
                             env={"CI": "true"})
        self.assertEqual((self.caller / "ci-reports/latest.md").read_text(), result.stdout)

    def test_non_git_fingerprints_include_source_but_exclude_reports(self):
        self.review(self.caller, self.plain, self.plain)
        first = (self.latest(self.plain).parent / "fingerprint").read_text()
        (self.plain / ".deep-review/old.md").write_text("generated output\n")
        self.review(self.caller, self.plain, self.plain)
        self.assertEqual((self.latest(self.plain).parent / "fingerprint").read_text(), first)
        (self.plain / "source.txt").write_text("changed actual source\n")
        self.review(self.caller, self.plain, self.plain)
        self.assertNotEqual((self.latest(self.plain).parent / "fingerprint").read_text(), first)

    def test_recovery_survives_report_creation_but_not_source_edits(self):
        self.review(self.caller, self.plain, self.plain, env={"FAIL_SYNTH": "1"}, code=1)
        failed_run = self.latest(self.plain).parent
        (self.plain / ".deep-review").mkdir()
        (self.plain / ".deep-review/old.md").write_text("old output\n")
        result = self.review(self.caller, self.plain, os.path.relpath(self.plain, self.caller))
        self.assertIn("Resuming interrupted", result.stderr)
        self.assertEqual(self.latest(self.plain).parent, failed_run)
        self.review(self.caller, self.plain, self.plain, env={"FAIL_SYNTH": "1"}, code=1)
        failed_run = self.latest(self.plain).parent
        (self.plain / "source.txt").write_text("new bytes must invalidate recovery\n")
        result = self.review(self.caller, self.plain, self.plain)
        self.assertNotIn("Resuming interrupted", result.stderr)
        self.assertNotEqual(self.latest(self.plain).parent, failed_run)

    def test_generated_tracked_reports_are_excluded_from_diffs_and_fingerprint(self):
        reports = self.repo / ".deep-review"
        reports.mkdir()
        (reports / "old.md").write_text("tracked generated report\n")
        self.git(self.repo, "add", ".deep-review/old.md")
        self.git(self.repo, "commit", "-qm", "tracked report fixture")
        (self.repo / "src/source.txt").write_text("uncommitted source\n")
        self.review(self.caller, self.repo, "--target", self.repo, "--changes")
        artifacts = self.latest(self.repo)
        first = (artifacts.parent / "fingerprint").read_text()
        self.assertNotIn(".deep-review", (artifacts / "changed-files.txt").read_text())
        self.assertNotIn(".deep-review", (artifacts / "review.diff").read_text())
        (reports / "old.md").write_text("changed generated report\n")
        self.review(self.caller, self.repo, "--target", self.repo, "--changes")
        self.assertEqual((self.latest(self.repo).parent / "fingerprint").read_text(), first)
        self.review(self.caller, self.repo, "--target", self.repo, "--branch")
        self.assertNotIn(".deep-review", (self.latest(self.repo) / "review.diff").read_text())

    def test_worktree_and_directory_symlink(self):
        worktree = self.root / "linked worktree"
        self.git(self.repo, "worktree", "add", "-qb", "linked", str(worktree), "HEAD")
        self.assertTrue((worktree / ".git").is_file())
        link = self.caller / "target-link"
        link.symlink_to(worktree / "src", target_is_directory=True)
        result = self.review(self.caller, worktree, "--target", link)
        self.assert_export(worktree, result.stdout)
        self.assertFalse((self.repo / ".deep-review").exists())

    def test_inherited_git_environment_does_not_override_target(self):
        result = self.review(self.caller, self.plain, self.plain,
                             env={"GIT_DIR": str(self.repo / ".git"),
                                  "GIT_WORK_TREE": str(self.repo),
                                  "GIT_INDEX_FILE": str(self.repo / ".git/index")})
        self.assert_export(self.plain, result.stdout)
        self.assertFalse((self.repo / ".deep-review").exists())

    def test_default_symlink_rejected_but_explicit_output_is_honored(self):
        (self.plain / ".deep-review").symlink_to(self.caller, target_is_directory=True)
        result = self.review(self.caller, self.plain, self.plain, code=1)
        self.assertIn("must not be a symlink", result.stderr)
        self.assertFalse((self.caller / "latest.md").exists())
        self.review(self.caller, self.plain, self.plain, "--output", "explicit.md")
        self.assertTrue((self.caller / "explicit.md").is_file())

    def test_model_option_value_is_not_mistaken_for_target(self):
        result = self.review(self.caller, self.plain, "--model", self.repo,
                             "--fast-model", self.repo / "src", self.plain)
        self.assert_export(self.plain, result.stdout)
        self.assertFalse((self.repo / ".deep-review").exists())

    def test_non_git_file_symlink_hashes_referent_contents(self):
        source = self.caller / "actual.txt"
        source.write_text("original bytes\n")
        link = self.plain / "file-link.txt"
        link.symlink_to(source)
        self.review(self.caller, self.plain, link)
        first = (self.latest(self.plain).parent / "fingerprint").read_text()
        source.write_text("updated bytes\n")
        self.review(self.caller, self.plain, link)
        self.assertNotEqual((self.latest(self.plain).parent / "fingerprint").read_text(), first)

    def test_git_file_target_is_a_literal_pathspec(self):
        target = self.repo / "src/[a].txt"
        sibling = self.repo / "src/a.txt"
        target.write_text("target bytes\n")
        sibling.write_text("sibling bytes\n")
        self.git(self.repo, "add", ".")
        self.git(self.repo, "commit", "-qm", "literal filename fixtures")
        self.review(self.caller, self.repo, target)
        first = (self.latest(self.repo).parent / "fingerprint").read_text()
        sibling.write_text("different sibling bytes\n")
        self.review(self.caller, self.repo, target)
        self.assertEqual((self.latest(self.repo).parent / "fingerprint").read_text(), first)
        target.write_text("different target bytes\n")
        self.review(self.caller, self.repo, target)
        self.assertNotEqual((self.latest(self.repo).parent / "fingerprint").read_text(), first)


if __name__ == "__main__":
    unittest.main(verbosity=2)
