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
PROVIDERS = ("codex", "claude", "copilot", "grok", "gemini")
MOCK = r'''#!/usr/bin/env python3
import json, os, pathlib, re, sys
args = sys.argv[1:]
provider = pathlib.Path(sys.argv[0]).name
prompt = args[-1] if provider == "codex" else args[args.index("-p") + 1]
model = args[args.index("--model") + 1] if "--model" in args else ""
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
    target = match(r"integer finding count to (.+)\.$")
elif "confidence scorer for a batch" in prompt:
    stage = "score-batch"
    target = match(r"^Score batch marker: (.+)$")
elif "final code-review triage editor" in prompt:
    stage = "final"
    target = match(r"^Write the final report to: (.+)$")
else:
    raise AssertionError(prompt)
with open(os.environ["CALL_LOG"], "a") as log:
    log.write(json.dumps({"provider": provider, "stage": stage, "model": model,
                          "args": args, "cwd": os.getcwd()}) + "\n")
if os.environ.get("FAIL_STAGE") == stage:
    sys.exit(42)
if stage == "extract":
    write(target, "1\n")
    write(pathlib.Path(target).parent / "finding-1.md", "TITLE: routing fixture\n")
elif stage == "score-batch":
    write(pathlib.Path(target).parent / "score-1.txt", "SCORE: 95\nREASON: Fixture.\n")
else:
    write(target, "# Provider routing fixture\n")
'''


class ProviderSelection(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="deep-review-provider-test-")
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
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

    def run_review(self, *args, direct=False, env=None):
        script = "deep-review-engine.sh" if direct else "deep-review.sh"
        return subprocess.run(
            ["bash", str(self.skill / "scripts" / script), "--target", str(self.target),
             "--max-concurrent", "2", "--model", "review model", "--fast-model",
             "fast model", "code", "python", *args], cwd=self.base,
            env=dict(self.env, **(env or {})), text=True, capture_output=True, timeout=25)

    def calls(self):
        return [json.loads(line) for line in self.log.read_text().splitlines()] if self.log.exists() else []

    def assert_pipeline(self, result, provider, durable=True):
        self.assertEqual(result.returncode, 0, result.stderr)
        calls = self.calls()
        self.assertEqual({call["provider"] for call in calls}, {provider})
        self.assertEqual(sorted(call["stage"] for call in calls),
                         sorted(["stack", "reviewer", "reviewer", "synthesis", "extract", "score-batch", "final"]))
        for call in calls:
            self.assertEqual(call["cwd"], str(self.target))
            fast = call["stage"] in ("stack", "extract", "score-batch")
            self.assertEqual(call["model"], "fast model" if fast else "review model")
            self.assertNotIn("--yolo", call["args"])
            self.assertNotIn("--resume", call["args"])
            self.assertNotIn("--continue", call["args"])
        if durable:
            artifacts = next((self.base / "state").glob("repos/*/runs/*/artifacts"))
            states = list((artifacts / "lifecycle").glob("*.state"))
            self.assertEqual(len(states), 7)
            for state in states:
                self.assertIn("provider=" + provider + "\n", state.read_text())
                self.assertIn("state=completed\n", state.read_text())
            self.assertIn("provider=" + provider + "\n", (artifacts / "request.txt").read_text())
            self.assertTrue((self.target / ".deep-review/latest.md").is_file())

    def test_all_callers_with_all_competing_clis_installed(self):
        for provider in PROVIDERS:
            with self.subTest(provider=provider):
                self.log.unlink(missing_ok=True)
                shutil.rmtree(self.base / "state", ignore_errors=True)
                result = self.run_review("--provider", "auto", env={"DEEP_REVIEW_CALLER": provider})
                self.assert_pipeline(result, provider)

    def test_direct_engine_uses_same_resolver(self):
        for provider in ("grok", "claude", "gemini"):
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
        self.assert_pipeline(self.run_review(env={"DEEP_REVIEW_CALLER": "grok",
            "CLAUDECODE": "1", "CODEX_THREAD_ID": "outer"}), "grok")

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
        (self.bin / "grok").unlink()
        for direct in (False, True):
            result = self.run_review(direct=direct, env={"DEEP_REVIEW_CALLER": "grok"})
            self.assertEqual(result.returncode, 127, result.stderr)
            self.assertIn("No fallback", result.stderr)
        self.assertEqual(self.calls(), [])

    def test_provider_failure_does_not_switch_engines(self):
        result = self.run_review(env={"DEEP_REVIEW_CALLER": "grok", "FAIL_STAGE": "synthesis"})
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual({call["provider"] for call in self.calls()}, {"grok"})

    def test_recovery_cannot_mix_providers(self):
        self.run_review(env={"DEEP_REVIEW_CALLER": "grok", "FAIL_STAGE": "synthesis"})
        self.log.unlink()
        result = self.run_review(env={"DEEP_REVIEW_CALLER": "claude"})
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn("Resuming interrupted", result.stderr)
        self.assertEqual(len(self.calls()), 7)
        self.assertEqual({call["provider"] for call in self.calls()}, {"claude"})

    def test_ci_still_requires_explicit_provider(self):
        result = self.run_review("--ci", env={"DEEP_REVIEW_CALLER": "grok"})
        self.assertEqual(result.returncode, 2, result.stderr)
        self.assertIn("requires a fixed --provider", result.stderr)
        self.assertEqual(self.calls(), [])

    def test_grok_and_gemini_native_arguments(self):
        self.run_review(env={"DEEP_REVIEW_CALLER": "grok"})
        for call in self.calls():
            self.assertIn("--sandbox", call["args"])
            self.assertEqual(call["args"][call["args"].index("--sandbox") + 1], "read-only")
            self.assertIn("--no-auto-update", call["args"])
        self.log.unlink()
        self.run_review(env={"DEEP_REVIEW_CALLER": "gemini"})
        for call in self.calls():
            self.assertIn("--approval-mode", call["args"])
            self.assertIn("auto_edit", call["args"])
            self.assertIn(str(self.skill), call["args"])
            self.assertEqual(call["args"].count("--include-directories"), 2)


if __name__ == "__main__":
    unittest.main(verbosity=2)
