#!/usr/bin/env bash
set -euo pipefail

# Integration contract for strict CI, with no network or paid model calls.
repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
runner="$repo_dir/skills/deep-review/scripts/deep-review.sh"
test_dir="$(mktemp -d "${TMPDIR:-/tmp}/deep-review-ci-test.XXXXXX")"
trap 'rm -rf "$test_dir"' EXIT
mkdir -p "$test_dir/bin" "$test_dir/repo"

cat >"$test_dir/bin/codex" <<'PY'
#!/usr/bin/env python3
import json
import os
import re
import sys
from pathlib import Path

prompt = sys.argv[sys.argv.index("-p") + 1] if "-p" in sys.argv else sys.argv[-1]
root = Path(os.environ["DEEP_REVIEW_ACTIVE_WORK_DIR"])
scenario = os.environ.get("FAKE_SCENARIO", "standard")
if "stack profiling instructions" in prompt:
    stage, target = "profile", root / "stack-context.md"
elif "specialized READ-ONLY" in prompt:
    stage = "reviewer"
    target = Path(re.search(r"^Write your complete Markdown findings to: (.+)$", prompt, re.M)[1])
elif "synthesis agent for a multi-agent" in prompt:
    stage, target = "synthesis", root / "REPORT.md"
elif "extract every distinct code-review finding" in prompt:
    stage, target = "extract", root / "findings/extracted.json"
elif "confidence scorer for a batch" in prompt:
    stage, target = "scores", None
elif "final code-review triage editor" in prompt:
    stage, target = "final", root / "triage.json"
else:
    raise RuntimeError("Unrecognized provider prompt")
with open(os.environ["FAKE_CALLS"], "a") as log:
    log.write(stage + "\n")
if scenario == "missing-" + stage:
    sys.exit(0)
findings = [{"id": index, "title": title, "classification": classification,
             "severity": "high", "source": "code-reviewer", "location": "app.txt:%d" % index,
             "details": "A concrete failure demonstrated by the reviewed code."}
            for index, title, classification in (
                (1, "New production risk", "NEW"), (2, "Existing blocker", "PRE-EXISTING"),
                (3, "Unconfirmed blocker", "NEW"), (4, "Useful improvement", "NEW"))]
if scenario == "empty":
    findings = []
if stage in ("profile", "reviewer", "synthesis"):
    status = "ERROR" if scenario == "partial-" + stage else "COMPLETE"
    target.write_text("REVIEW_STATUS: " + status + "\n# Findings\nConcrete review evidence.\n")
elif stage == "extract":
    target.parent.mkdir(exist_ok=True)
    if scenario == "invalid-extract":
        target.write_text("{broken JSON")
    elif scenario == "excessive-extract":
        target.write_text(json.dumps({"findings": findings * 51}))
    elif scenario == "invalid-extracted-id":
        findings[0]["id"] = 2
        target.write_text(json.dumps({"findings": findings}))
    else:
        target.write_text(json.dumps({"findings": findings}))
elif stage == "scores":
    ids = re.search(r"^Batch findings: (.+)$", prompt, re.M)[1].split()
    for value in ids:
        index = int(value)
        if scenario == "missing-one-score" and index == 1:
            continue
        score = {1: 95, 2: 99, 3: 79, 4: 90}[index]
        if scenario == "boundary" and index == 3:
            score = 80
        output = "SCORE: %d\nREASON: Independently validated against the code.\n" % score
        if scenario == "invalid-score" and index == 1:
            output = "SCORE: 999\nREASON: Bad range.\n"
        (root / ("findings/score-%d.txt" % index)).write_text(output)
elif stage == "final":
    triage = [{"id": finding["id"], "priority": {1: "P1", 2: "P0", 3: "P0", 4: "P2"}[finding["id"]],
               "rationale": "Concrete risk confirmed from source.", "fix": "Check input before processing."}
              for finding in findings]
    if scenario == "invented-id":
        triage[0]["id"] = 999
    elif scenario == "duplicate-id":
        triage[0]["id"] = 2
    elif scenario == "omitted-id":
        triage.pop()
    elif scenario == "noise":
        for item in triage:
            item["priority"] = None
    if scenario == "invalid-final":
        target.write_text("# Everything is fine")
    else:
        target.write_text(json.dumps({"summary": "Review completed with evidence.", "triage": triage}))
if scenario == "fail-" + stage:
    sys.exit(9)  # A complete-looking output must not hide process failure.
PY
chmod +x "$test_dir/bin/codex"
ln -s codex "$test_dir/bin/copilot"
export PATH="$test_dir/bin:$PATH"
export DEEP_REVIEW_SLOT_DIR="$test_dir/slots"
export DEEP_REVIEW_MEMORY_RESERVE_MB=0
export DEEP_REVIEW_MEMORY_PER_WORKER_MB=1
export DEEP_REVIEW_KEEP_COMPLETED_RUNS=0
export DEEP_REVIEW_SCORE_BATCH_SIZE=2
export CONFIDENCE_THRESHOLD=80
unset DEEP_REVIEW_PROVIDER DEEP_REVIEW_STATE_DIR DEEP_REVIEW_RESULTS_DIR DEEP_REVIEW_RESULT_FILE REVIEW_BASE || true
cd "$test_dir/repo"
git init -q
git config user.name "CI Test"
git config user.email "ci-test@example.invalid"
printf 'base\n' >app.txt
git add app.txt
git commit -qm base
git branch -M main
git switch -qc feature
printf 'changed\n' >>app.txt
git commit -qam feature
# Existing path named like the base ref must not change the wrapper scope.
mkdir main

index=0
run_case() {
  expected="$1"; scenario="$2"; shift 2
  index=$((index + 1))
  case_dir="$test_dir/case-$index"
  mkdir -p "$case_dir"
  export FAKE_SCENARIO="$scenario" FAKE_CALLS="$case_dir/calls" GITHUB_OUTPUT="$case_dir/github-output"
  : >"$FAKE_CALLS"
  : >"$GITHUB_OUTPUT"
  actual=0
  bash "$runner" --artifacts-dir "$case_dir/state" --results-dir "$case_dir/results" \
    --output "$case_dir/export/review.md" --max-concurrent 2 "$@" >"$case_dir/stdout" 2>"$case_dir/stderr" || actual=$?
  if [ "$actual" -ne "$expected" ]; then
    cat "$case_dir/stderr" >&2
    echo "$scenario: expected exit $expected; got $actual" >&2
    exit 1
  fi
  if [ "$expected" -ne 2 ]; then
    python3 - "$case_dir" "$expected" <<'PY'
import json
import sys
from pathlib import Path
root, expected = Path(sys.argv[1]), int(sys.argv[2])
data = json.loads((root / "export/review.json").read_text())
assert (root / "export/review.md").is_file()
assert (root / "results/latest.json").is_file()
assert data["status"] == "error" if expected == 1 else data["status"] in ("complete", "no_changes")
assert data["gate"]["passed"] is (expected == 0)
outputs = dict(line.split("=", 1) for line in (root / "github-output").read_text().splitlines())
assert Path(outputs["deep_review_result"]).is_file()
assert Path(outputs["deep_review_json"]).is_file()
assert Path(outputs["deep_review_artifacts"], "review.json").is_file()
if expected in (0, 3):
    assert (root / "stdout").read_bytes() == (root / "export/review.md").read_bytes()
PY
  fi
}

run_case 2 standard --ci --base main code
run_case 2 standard --ci --provider codex code
run_case 2 standard --provider codex --base main --fail-on p1 code
run_case 2 standard --ci --provider codex --base main --fail-on p9 code
run_case 2 standard --ci --provider codex --base HEAD nonexistent-aspect
run_case 0 standard --ci --provider codex --base HEAD --fail-on p0 code
[ ! -s "$FAKE_CALLS" ]
python3 - "$case_dir/export/review.json" <<'PY'
import json, sys
assert json.load(open(sys.argv[1]))["status"] == "no_changes"
PY
run_case 0 standard --ci --provider codex --base main code
run_case 0 standard --ci --provider codex --base main --fail-on p0 code
run_case 3 standard --ci --provider codex --base main --fail-on p1 code
python3 - "$case_dir/export/review.json" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
assert data["scope"] == "branch"
assert data["gate"]["finding_ids"] == [1]
assert data["findings"][1]["classification"] == "PRE-EXISTING"
assert data["findings"][2]["included"] is False
PY
run_case 3 standard --ci --provider codex --base main --fail-on p2 code
run_case 3 standard --ci --provider copilot --base main --fail-on p1 code
run_case 3 boundary --ci --provider codex --base main --fail-on p0 code
run_case 0 noise --ci --provider codex --base main --fail-on p2 code
CONFIDENCE_THRESHOLD=96 run_case 0 standard --ci --provider codex --base main --fail-on p1 code
run_case 0 empty --ci --provider codex --base main --fail-on p2 code
! grep -q '^scores$' "$FAKE_CALLS"

for stage in reviewer synthesis extract scores final; do
  run_case 1 "fail-$stage" --ci --provider codex --base main code
  run_case 1 "missing-$stage" --ci --provider codex --base main code
done
run_case 1 fail-profile --ci --provider codex --base main php
run_case 1 partial-profile --ci --provider codex --base main php
run_case 1 partial-reviewer --ci --provider codex --base main code
run_case 1 partial-synthesis --ci --provider codex --base main code
for scenario in invalid-extract excessive-extract invalid-extracted-id missing-one-score invalid-score \
                invalid-final invented-id duplicate-id omitted-id; do
  run_case 1 "$scenario" --ci --provider codex --base main code
done

# Explicit environment provider/base are supported, including base refs that name paths.
DEEP_REVIEW_PROVIDER=codex REVIEW_BASE=main run_case 0 empty --ci code

# No-change jobs do not need a provider installed, even with an explicit provider.
mkdir "$test_dir/no-provider-bin"
for utility in bash python3 git mkdir mktemp id stat chmod cksum awk cat dirname basename find sort wc tr sed \
               date cp rm ln mv head grep ps; do
  ln -s "$(command -v "$utility")" "$test_dir/no-provider-bin/$utility"
done
PATH="$test_dir/no-provider-bin" run_case 0 standard --ci --provider codex --base HEAD code
[ ! -s "$FAKE_CALLS" ]

# CI must not recover an interrupted run's completed-looking JSON or provider outputs.
run_case 0 standard --ci --provider codex --base main code
old_run="$(find "$case_dir/state" -name status -not -path '*/artifacts/*' -print)"
printf 'interrupted\n' >"$old_run"
export FAKE_SCENARIO=invalid-final
actual=0
bash "$runner" --ci --provider codex --base main code --artifacts-dir "$case_dir/state" \
  --results-dir "$case_dir/results" --output "$case_dir/export/review.md" --max-concurrent 2 \
  >"$case_dir/retry-stdout" 2>"$case_dir/retry-stderr" || actual=$?
[ "$actual" -eq 1 ]
! grep -q 'Resuming interrupted' "$case_dir/retry-stderr"
python3 - "$case_dir/export/review.json" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
assert data["status"] == "error"
assert "invalid final triage output" in data["summary"]
PY
echo "deep-review CI tests passed ($index fake-provider cases)"
