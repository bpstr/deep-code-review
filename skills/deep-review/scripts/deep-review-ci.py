#!/usr/bin/env python3
"""Validate CI review data, render reports, and apply a deterministic findings gate.

Python standard library only. Model output never determines process exit status directly.
"""

import argparse
import json
import re
import sys
from pathlib import Path

MAX_FINDINGS = 200
MAX_BYTES = 2 * 1024 * 1024


def require(condition, message):
    if not condition:
        raise ValueError(message)


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        require(key not in result, "duplicate JSON key: " + key)
        result[key] = value
    return result


def read_text(path):
    require(path.is_file(), "missing output: " + str(path))
    require(path.stat().st_size <= MAX_BYTES, "output exceeds 2 MiB: " + str(path))
    value = path.read_text(encoding="utf-8")
    require(value.strip(), "empty output: " + str(path))
    return value


def read_json(path):
    return json.loads(read_text(path), object_pairs_hook=unique_object)


def fields(value, expected, label):
    require(type(value) is dict and set(value) == set(expected), label + " has invalid fields")


def string(value, label, limit=12000):
    require(isinstance(value, str) and 0 < len(value.strip()) <= limit, label + " must be a nonempty string")
    require("\x00" not in value, label + " contains a NUL byte")
    return value


def extraction(directory, materialize=False):
    data = read_json(directory / "findings" / "extracted.json")
    fields(data, ["findings"], "extraction")
    findings = data["findings"]
    require(type(findings) is list and len(findings) <= MAX_FINDINGS,
            "extraction must contain at most 200 findings")
    for index, finding in enumerate(findings, 1):
        fields(finding, ["id", "title", "classification", "severity", "source", "location", "details"], "finding")
        require(type(finding["id"]) is int and finding["id"] == index,
                "extracted IDs must be consecutive integers starting at 1")
        require(finding["classification"] in ("NEW", "PRE-EXISTING"), "invalid finding classification")
        for key in ("title", "severity", "source", "location", "details"):
            string(finding[key], "finding " + key, 12000 if key == "details" else 1000)
        if materialize:
            content = "\n".join(key.upper() + ": " + str(finding[key]) for key in
                                ("id", "title", "classification", "severity", "source", "location", "details"))
            (directory / "findings" / ("finding-%d.md" % index)).write_text(content + "\n", encoding="utf-8")
    if materialize:
        (directory / "findings" / "count.txt").write_text(str(len(findings)) + "\n", encoding="utf-8")
    return findings


def scores(directory, findings):
    result = {}
    for finding in findings:
        finding_id = finding["id"]
        raw = read_text(directory / "findings" / ("score-%d.txt" % finding_id))
        match = re.fullmatch(r"SCORE: (0|[1-9][0-9]?|100)\r?\nREASON: ([^\r\n]+)\r?\n?", raw)
        require(match is not None, "invalid score for finding %d; expected SCORE and REASON lines" % finding_id)
        reason = string(match.group(2), "confidence reason", 2000)
        result[finding_id] = {"confidence": int(match.group(1)), "confidence_reason": reason}
    return result


def atomic_write(path, value):
    temporary = path.with_name(path.name + ".tmp")
    temporary.write_text(value, encoding="utf-8")
    temporary.replace(path)


def report(args, status, summary, findings):
    threshold = {"none": -1, "p0": 0, "p1": 1, "p2": 2}[args.fail_on]
    blockers = [item["id"] for item in findings if item["included"] and
                item["classification"] == "NEW" and int(item["priority"][1]) <= threshold]
    data = {
        "schema_version": 1,
        "status": status,
        "provider": args.provider,
        "scope": args.scope,
        "base": args.base or None,
        "head": args.head or None,
        "confidence_threshold": args.confidence,
        "summary": summary,
        "findings": findings,
        "gate": {"fail_on": args.fail_on, "classification": "NEW", "finding_ids": blockers,
                 "passed": status != "error" and not blockers},
    }
    markdown = ["# Deep Code Review", "", "Status: **%s**" % status, "", summary, ""]
    if status == "error":
        markdown.extend(["The review is incomplete. Consult the stage logs and partial outputs in the artifacts.", ""])
    included = [finding for finding in findings if finding["included"]]
    for finding in included:
        markdown.extend([
            "## %s · %s — %s" % (finding["priority"], finding["classification"], finding["title"]), "",
            "Location: %s · Confidence: %d/100 · Finding: %d" %
            (finding["location"], finding["confidence"], finding["id"]), "",
            finding["details"], "", "Rationale: " + finding["rationale"], "", "Suggested fix: " + finding["fix"], "",
        ])
    if status != "error" and not included:
        markdown.extend(["No findings remain after triage and the confidence filter.", ""])
    if findings:
        markdown.extend(["Reviewed %d extracted findings; %d were excluded by confidence or triage." %
                         (len(findings), len(findings) - len(included)), ""])
    gate_result = "failed: review incomplete" if status == "error" else (
        "failed on finding IDs " + ", ".join(map(str, blockers)) if blockers else "passed")
    markdown.extend(["Gate: **%s**. Policy: `%s`, NEW findings only, confidence ≥ %d." %
                     (gate_result, args.fail_on, args.confidence), ""])
    args.directory.mkdir(parents=True, exist_ok=True)
    atomic_write(args.directory / "review.json", json.dumps(data, ensure_ascii=False, indent=2) + "\n")
    atomic_write(args.directory / "FINAL.md", "\n".join(markdown))
    atomic_write(args.directory / "review.md", "\n".join(markdown))
    return 1 if status == "error" else (3 if blockers else 0)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("markdown", "extract", "scores", "finalize", "no-changes", "error"))
    parser.add_argument("--directory", required=True, type=Path)
    parser.add_argument("--file", type=Path)
    parser.add_argument("--provider", default="unknown")
    parser.add_argument("--scope", default="branch", choices=("branch", "changes", "path"))
    parser.add_argument("--base", default="")
    parser.add_argument("--head", default="")
    parser.add_argument("--confidence", type=int, choices=range(101), default=80)
    parser.add_argument("--fail-on", choices=("none", "p0", "p1", "p2"), default="none")
    parser.add_argument("--message", default="A required review stage failed or produced invalid output.")
    args = parser.parse_args()
    try:
        if args.command == "markdown":
            require(args.file is not None, "Markdown validation requires --file")
            content = read_text(args.file).splitlines()
            require(content[0] == "REVIEW_STATUS: COMPLETE" and "\n".join(content[1:]).strip(),
                    "stage did not declare a complete review: " + str(args.file))
            return 0
        if args.command == "error":
            return report(args, "error", args.message, [])
        if args.command == "no-changes":
            return report(args, "no_changes", "No changed files were found in the requested scope. No provider calls were made.", [])
        findings = extraction(args.directory, materialize=args.command == "extract")
        if args.command == "extract":
            print(len(findings))
            return 0
        confidence = scores(args.directory, findings)
        if args.command == "scores":
            return 0
        final = read_json(args.directory / "triage.json")
        fields(final, ["summary", "triage"], "triage output")
        string(final["summary"], "summary")
        require(type(final["triage"]) is list and len(final["triage"]) == len(findings),
                "triage must contain exactly one entry for every extracted finding")
        by_id = {}
        for item in final["triage"]:
            fields(item, ["id", "priority", "rationale", "fix"], "triage finding")
            finding_id = item["id"]
            require(type(finding_id) is int and 1 <= finding_id <= len(findings) and finding_id not in by_id,
                    "triage references duplicate or unknown finding ID")
            require(item["priority"] in ("P0", "P1", "P2", None), "invalid triage priority")
            string(item["rationale"], "rationale")
            string(item["fix"], "fix")
            by_id[finding_id] = item
        merged = []
        for finding in findings:
            finding_id = finding["id"]
            item = dict(finding, **confidence[finding_id])
            item.update(by_id[finding_id])
            item["included"] = item["priority"] is not None and item["confidence"] >= args.confidence
            merged.append(item)
        return report(args, "complete", final["summary"], merged)
    except (ValueError, OSError, UnicodeError, KeyError, TypeError) as error:
        print("CI report validation failed: " + str(error), file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
