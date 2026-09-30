#!/usr/bin/env python3
"""Credential-free routing regression tests; run the real pipeline with CLI doubles."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
BASH = os.environ.get("BASH_TEST", "/bin/bash")
PROVIDERS = ("codex", "claude", "copilot", "grok", "gemini", "muse")
STAGES = ["stack", "reviewer", "reviewer", "synthesis", "extract", "score-batch", "final"]
MOCK = r'''#!/usr/bin/env python3
import json, os, pathlib, re, sys
args = sys.argv[1:]
provider = pathlib.Path(sys.argv[0]).name
prompt = args[-1] if provider in ("codex", "muse") else args[args.index("-p") + 1]
model = args[args.index("--model") + 1] if "--model" in args else ""
ci = os.environ.get("DEEP_REVIEW_CI") == "1"
if provider == "muse":
    # Reject Claude/Codex flags and extra positional arguments rather than letting
    # a permissive fake conceal an invalid native Muse command.
    assert args[0] == "exec", args
    i = 1
    flags = []
    while i < len(args) - 1:
        flag = args[i]
        assert flag not in flags, args
        flags.append(flag)
        if flag in ("--disable-approval", "--no-session-log"):
            i += 1
        elif flag in ("--workspace", "--model"):
            assert i + 1 < len(args) - 1, args
            if flag == "--workspace":
                assert pathlib.Path(args[i + 1]).resolve() == pathlib.Path.cwd(), args
            i += 2
        else:
            raise AssertionError("Unexpected Muse argument: " + flag)
    assert i == len(args) - 1 and prompt, args
    assert set(("--disable-approval", "--no-session-log", "--workspace")) <= set(flags), args
    if os.environ.get("DEEP_REVIEW_PERSISTENT_RUN_DIR"):
        work = pathlib.Path(os.environ["DEEP_REVIEW_ACTIVE_WORK_DIR"])
        assert (work / ".shims/muse").is_file(), "Muse skipped lifecycle shim"
        assert os.environ.get("DEEP_REVIEW_REAL_MUSE"), "Missing real Muse executable"
        assert any(pathlib.Path(os.environ["DEEP_REVIEW_GLOBAL_SLOT_DIR"]).glob("[0-9]*")), "No provider slot"
def match(pattern):
    found = re.search(pattern, prompt, re.M)
    assert found, (pattern, prompt)
    return found.group(1)
def write(path, text):
    path = pathlib.Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text)
if "stack profiling instructions" in prompt:
    stage = "stack"
    target = match(r"^Write the shared profile to: (.+)$")
elif "specialized READ-ONLY" in prompt:
    stage = "reviewer"
    target = match(r"^Write your complete Markdown findings to: (.+)$")
elif "synthesis agent for a multi-agent" in prompt:
    stage = "synthesis"
    target = match(r"write the merged report to: (.+)$")
elif "extract every distinct" in prompt:
    stage = "extract"
    target = match(r"JSON only \(no Markdown fences\) to (.+)\.$") if ci else match(r"integer finding count to (.+)\.$")
elif "confidence scorer for a batch" in prompt:
    stage = "score-batch"
    target = match(r"^Score batch marker: (.+)$")
elif "final code-review triage editor" in prompt:
    stage = "final"
    target = match(r"to: (.+/triage\.json)$") if ci else match(r"^Write the final report to: (.+)$")
else:
    raise AssertionError(prompt)
with open(os.environ["CALL_LOG"], "a") as log:
    log.write(json.dumps({"provider": provider, "stage": stage, "model": model,
                          "args": args, "cwd": os.getcwd()}) + "\n")
if os.environ.get("FAIL_STAGE") == stage:
    sys.exit(42)
if stage == "extract":
    if ci:
        write(target, json.dumps({"findings": [{"id": 1, "title": "Routing fixture",
              "classification": "NEW", "severity": "Important", "source": "code-reviewer",
              "location": "example.py:1", "details": "Synthetic routing fixture."}]}))
    else:
        write(target, "1\n")
        write(pathlib.Path(target).parent / "finding-1.md", "TITLE: routing fixture\n")
elif stage == "score-batch":
    write(pathlib.Path(target).parent / "score-1.txt", "SCORE: 95\nREASON: Fixture.\n")
elif stage == "final" and ci:
    write(target, json.dumps({"summary": "Routing fixture", "triage": [
          {"id": 1, "priority": "P2", "rationale": "Synthetic fixture.", "fix": "Fixture only."}]}))
else:
    write(target, ("REVIEW_STATUS: COMPLETE\n" if ci else "") + "# Provider routing fixture\n")
'''


class ProviderSelection(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="deep-review-provider-test-")
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name).resolve()
        self.skill = self.base / "installed skill"
        shutil.copytree(ROOT / "skills/deep-review/scripts", self.skill / "scripts")
        # Prompt content is deliberately stubbed: these tests exercise orchestration,
        # not model review quality. All actual runner/shim/helper scripts are copied.
        for name in ("support/stack-profiler.md", "support/architecture-review.md",
                     "support/architecture-context.md", "support/finding-validation.md",
                     "agents/python-reviewer.md", "agents/code-reviewer.md",
                     "agents/synthesizer.md"):
            path = self.skill / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text("Routing fixture instructions.\n")
        # Cache hashing includes this optional scanner; it is never executed here.
        scanner = self.skill / "scripts/architecture-evidence.py"
        if not scanner.exists():
            scanner.write_text("# Unused in provider-routing tests.\n")
        self.target = self.base / "target with spaces"
        self.target.mkdir()
        (self.target / "example.py").write_text("print('fixture')\n")
        self.bin = self.base / "bin"
        self.bin.mkdir()
        for provider in PROVIDERS:
            path = self.bin / provider
            path.write_text(MOCK)
            path.chmod(0o700)
        (self.bin / "python3").symlink_to(sys.executable)
        self.log = self.base / "calls.jsonl"
        # Do not let the test host's client, credentials or private config leak in.
        self.env = {
            "PATH": str(self.bin) + ":/usr/bin:/bin", "HOME": str(self.base / "home"),
            "TMPDIR": str(self.base / "tmp"), "CALL_LOG": str(self.log),
            "DEEP_REVIEW_STATE_DIR": str(self.base / "state"),
            "DEEP_REVIEW_SLOT_DIR": str(self.base / "slots"),
            "DEEP_REVIEW_PROVIDER_TIMEOUT_SECONDS": "15",
        }
        Path(self.env["HOME"]).mkdir()
        Path(self.env["TMPDIR"]).mkdir()

    def run_review(self, *args, direct=False, env=None, models=True):
        script = "deep-review-engine.sh" if direct else "deep-review.sh"
        model_args = ["--model", "review model", "--fast-model", "fast model"] if models else []
        return subprocess.run(
            [BASH, str(self.skill / "scripts" / script), "--target", str(self.target),
             "--max-concurrent", "2", *model_args, "code", "python", *args], cwd=self.base,
            env=dict(self.env, **(env or {})), text=True, capture_output=True, timeout=25)

    def calls(self):
        return [json.loads(line) for line in self.log.read_text().splitlines()] if self.log.exists() else []

    def reset_run(self):
        self.log.unlink(missing_ok=True)
        shutil.rmtree(self.base / "state", ignore_errors=True)

    def assert_pipeline(self, result, provider, durable=True, models=True, ci=False):
        self.assertEqual(result.returncode, 0, result.stderr)
        calls = self.calls()
        self.assertEqual({call["provider"] for call in calls}, {provider})
        self.assertEqual(sorted(call["stage"] for call in calls), sorted(STAGES))
        for call in calls:
            self.assertEqual(call["cwd"], str(self.target))
            fast = call["stage"] in ("stack", "extract", "score-batch")
            expected_model = ("fast model" if fast else "review model") if models else ""
            self.assertEqual(call["model"], expected_model)
            for forbidden in ("--yolo", "--resume", "--continue", "--session-id", "--disable-sandbox"):
                self.assertNotIn(forbidden, call["args"])
        if durable:
            artifacts = next((self.base / "state").glob("repos/*/runs/*/artifacts"))
            states = list((artifacts / "lifecycle").glob("*.state"))
            self.assertEqual(len(states), len(STAGES))
            actual_stages = []
            for state in states:
                text = state.read_text()
                self.assertIn("provider=" + provider + "\n", text)
                self.assertIn("state=completed\n", text)
                actual_stages.append(next(line[6:] for line in text.splitlines() if line.startswith("stage=")))
            self.assertEqual(sorted(actual_stages), sorted(STAGES))
            self.assertIn("provider=" + provider + "\n", (artifacts / "request.txt").read_text())
            markers = artifacts.parent / "checkpoints/complete"
            for marker in ("stack-context.md", "code-reviewer.md", "python-reviewer.md", "REPORT.md",
                           "findings/score-batch-1.complete",
                           "findings/extracted.json" if ci else "findings/count.txt",
                           "triage.json" if ci else "FINAL.md"):
                self.assertTrue((markers / marker).is_file(), marker)
            if not ci:
                self.assertTrue((self.target / ".deep-review/latest.md").is_file())
            self.assertEqual((self.target / "example.py").read_text(), "print('fixture')\n")
            self.assertFalse((self.target / ".muse").exists())

    def test_all_callers_with_all_competing_clis_installed(self):
        for provider in PROVIDERS:
            with self.subTest(provider=provider):
                self.reset_run()
                result = self.run_review("--provider", "auto", env={"DEEP_REVIEW_CALLER": provider})
                self.assert_pipeline(result, provider)

    def test_direct_engine_uses_same_resolver(self):
        for provider in PROVIDERS:
            with self.subTest(provider=provider):
                self.log.unlink(missing_ok=True)
                self.assert_pipeline(self.run_review(direct=True, env={"DEEP_REVIEW_CALLER": provider}),
                                     provider, durable=False)

    def test_explicit_provider_overrides_environment_and_caller(self):
        result = self.run_review("--provider", "grok", env={
            "DEEP_REVIEW_CALLER": "claude", "DEEP_REVIEW_PROVIDER": "codex"})
        self.assert_pipeline(result, "grok")

    def test_environment_provider_overrides_caller(self):
        self.assert_pipeline(self.run_review(env={"DEEP_REVIEW_PROVIDER": "claude",
            "DEEP_REVIEW_CALLER": "grok"}), "claude")

    def test_explicit_caller_beats_inherited_outer_session(self):
        for provider in ("grok", "muse"):
            with self.subTest(provider=provider):
                self.reset_run()
                self.assert_pipeline(self.run_review(env={"DEEP_REVIEW_CALLER": provider,
                    "CLAUDECODE": "1", "CODEX_THREAD_ID": "outer"}), provider)

    def test_native_claude_marker_beats_installed_codex(self):
        self.assert_pipeline(self.run_review(env={"CLAUDECODE": "1"}), "claude")

    def test_native_codex_marker(self):
        self.assert_pipeline(self.run_review(env={"CODEX_THREAD_ID": "native"}), "codex")

    def test_unknown_caller_never_uses_installed_cli(self):
        for direct in (False, True):
            result = self.run_review(direct=direct)
            self.assertEqual(result.returncode, 2, result.stderr)
            self.assertIn("Cannot identify", result.stderr)
        self.assertEqual(self.calls(), [])

    def test_conflicting_native_markers_fail_closed(self):
        result = self.run_review(env={"CLAUDECODE": "1", "CODEX_THREAD_ID": "outer"})
        self.assertEqual(result.returncode, 2, result.stderr)
        self.assertIn("Conflicting", result.stderr)
        self.assertEqual(self.calls(), [])

    def test_unsupported_caller_and_provider_fail_closed(self):
        for env in ({"DEEP_REVIEW_CALLER": "other-client"}, {"DEEP_REVIEW_PROVIDER": "typo"}):
            result = self.run_review(env=env)
            self.assertEqual(result.returncode, 2, result.stderr)
            self.assertIn("Unsupported provider", result.stderr)
        self.assertEqual(self.calls(), [])

    def test_missing_selected_cli_does_not_fall_back(self):
        for provider in ("grok", "muse"):
            (self.bin / provider).unlink()
            for direct in (False, True):
                with self.subTest(provider=provider, direct=direct):
                    result = self.run_review(direct=direct, env={"DEEP_REVIEW_CALLER": provider})
                    self.assertEqual(result.returncode, 127, result.stderr)
                    self.assertIn("No fallback", result.stderr)
        self.assertEqual(self.calls(), [])

    def test_provider_failure_does_not_switch_engines(self):
        for provider in ("grok", "muse"):
            with self.subTest(provider=provider):
                self.reset_run()
                result = self.run_review(env={"DEEP_REVIEW_CALLER": provider, "FAIL_STAGE": "synthesis"})
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual({call["provider"] for call in self.calls()}, {provider})

    def test_recovery_cannot_mix_providers(self):
        for provider in ("grok", "muse"):
            with self.subTest(provider=provider):
                self.reset_run()
                failed = self.run_review(env={"DEEP_REVIEW_CALLER": provider, "FAIL_STAGE": "synthesis"})
                self.assertNotEqual(failed.returncode, 0)
                self.log.unlink()
                result = self.run_review(env={"DEEP_REVIEW_CALLER": "claude"})
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertNotIn("Resuming interrupted", result.stderr)
                self.assertEqual(len(self.calls()), 7)
                self.assertEqual({call["provider"] for call in self.calls()}, {"claude"})

    def test_ci_still_requires_explicit_provider(self):
        for provider in ("grok", "muse"):
            result = self.run_review("--ci", env={"DEEP_REVIEW_CALLER": provider})
            self.assertEqual(result.returncode, 2, result.stderr)
            self.assertIn("requires a fixed --provider", result.stderr)
        self.assertEqual(self.calls(), [])

    def test_grok_and_gemini_native_arguments(self):
        self.assert_pipeline(self.run_review(env={"DEEP_REVIEW_CALLER": "grok"}), "grok")
        for call in self.calls():
            self.assertIn("--sandbox", call["args"])
            self.assertEqual(call["args"][call["args"].index("--sandbox") + 1], "read-only")
            self.assertIn("--no-auto-update", call["args"])
        self.reset_run()
        self.assert_pipeline(self.run_review(env={"DEEP_REVIEW_CALLER": "gemini"}), "gemini")
        for call in self.calls():
            self.assertIn("--approval-mode", call["args"])
            self.assertIn("auto_edit", call["args"])
            self.assertIn(str(self.skill), call["args"])
            self.assertEqual(call["args"].count("--include-directories"), 2)

    def test_muse_explicit_and_environment_selection(self):
        result = self.run_review("--provider", "muse", env={
            "DEEP_REVIEW_PROVIDER": "codex", "DEEP_REVIEW_CALLER": "claude"})
        self.assert_pipeline(result, "muse")
        self.reset_run()
        self.assert_pipeline(self.run_review(env={"DEEP_REVIEW_PROVIDER": "muse",
            "DEEP_REVIEW_CALLER": "codex"}), "muse")

    def test_muse_native_arguments_without_model_override(self):
        result = self.run_review(models=False, env={"DEEP_REVIEW_CALLER": "muse"})
        self.assert_pipeline(result, "muse", models=False)
        for call in self.calls():
            self.assertEqual(call["args"][:-1], ["exec", "--disable-approval",
                "--no-session-log", "--workspace", str(self.target)])
            self.assertIn("Muse execution constraints:", call["args"][-1])
            self.assertNotIn("--trust-workspace", call["args"])
            self.assertNotIn("--model", call["args"])

    def test_muse_recovers_completed_stages(self):
        failed = self.run_review(env={"DEEP_REVIEW_CALLER": "muse", "FAIL_STAGE": "synthesis"})
        self.assertNotEqual(failed.returncode, 0)
        runs = list((self.base / "state").glob("repos/*/runs/*"))
        self.assertEqual(len(runs), 1)
        self.assertTrue((runs[0] / "checkpoints/complete/stack-context.md").is_file())
        self.log.unlink()
        result = self.run_review(env={"DEEP_REVIEW_CALLER": "muse"})
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("Resuming interrupted", result.stderr)
        self.assertEqual(list((self.base / "state").glob("repos/*/runs/*")), runs)
        self.assertEqual([call["stage"] for call in self.calls()],
                         ["synthesis", "extract", "score-batch", "final"])
        self.assertEqual({call["provider"] for call in self.calls()}, {"muse"})

    def test_muse_ci_uses_native_cli(self):
        result = self.run_review("--ci", "--provider", "muse")
        self.assert_pipeline(result, "muse", ci=True)
        report = next((self.base / "state").glob("repos/*/runs/*/artifacts/review.json"))
        self.assertEqual(json.loads(report.read_text())["provider"], "muse")
        self.assertFalse((self.target / ".deep-review").exists())

    def test_muse_unavailable_in_ci_fails_without_fallback(self):
        (self.bin / "muse").unlink()
        result = self.run_review("--ci", "--provider", "muse")
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertIn("provider 'muse' is not installed", result.stderr)
        self.assertEqual(self.calls(), [])

    def test_credentials_are_not_caller_identity(self):
        result = self.run_review(env={"META_API_KEY": "fake-test-only", "MUSE_SESSION_ID": "outer"})
        self.assertEqual(result.returncode, 2, result.stderr)
        self.assertEqual(self.calls(), [])


if __name__ == "__main__":
    unittest.main(verbosity=2)
