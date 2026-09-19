#!/usr/bin/env python3
"""Optional, bounded scanner evidence. Python stdlib only; no installs or shell eval.

Execution is explicit consent to trust project tools/configuration, NOT a sandbox.
Default reviews never invoke this helper. Raw output/snippets are not persisted.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import signal
import subprocess
import tempfile

MAX_BYTES = 8 * 1024 * 1024
MAX_CANDIDATES = 50
EXCLUDED = {'.git', 'node_modules', 'vendor', 'dist', 'build', 'coverage', '__pycache__'}
CONFIGS = {
    'jscpd': ('.jscpd.json', '.config/jscpd.json'),
    'dependency-cruiser': ('.dependency-cruiser.cjs', '.dependency-cruiser.js', '.dependency-cruiser.mjs', '.dependency-cruiser.json'),
    'deptrac': ('deptrac.yaml', 'deptrac.yml', 'deptrac.php'),
    'semgrep': ('.semgrep.yml', '.semgrep.yaml'),
}
REPORTS = {'jscpd': 'jscpd-report.json', 'dependency-cruiser': 'dependency-cruiser.json',
           'deptrac': 'deptrac.json', 'semgrep': 'semgrep.json'}


def run_command(argv, cwd, timeout):
    """No shell; bound wall time and stdout, terminate the entire process group."""
    def limits():
        import resource
        resource.setrlimit(resource.RLIMIT_FSIZE, (MAX_BYTES, MAX_BYTES))

    with tempfile.TemporaryFile() as output:
        proc = subprocess.Popen(argv, cwd=str(cwd), stdout=output, stderr=subprocess.DEVNULL,
                                stdin=subprocess.DEVNULL, start_new_session=True,
                                preexec_fn=limits)
        try:
            status = proc.wait(timeout=timeout)
        finally:
            # Also remove lingering descendants after a successful parent exit.
            try:
                os.killpg(proc.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            proc.wait()
        output.seek(0)
        data = output.read(MAX_BYTES + 1)
        if len(data) > MAX_BYTES:
            raise ValueError('oversized output')
        return status, data


def load_report(path):
    if path.is_symlink() or not path.is_file() or path.stat().st_size > MAX_BYTES:
        raise ValueError('missing, symlinked or oversized report')
    data = path.read_bytes()
    if len(data) > MAX_BYTES:
        raise ValueError('oversized report')
    value = json.loads(data)
    if not isinstance(value, dict):
        raise ValueError('unsupported report')
    return value


def location(root, cwd, value, start=None, end=None):
    if not isinstance(value, str) or len(value) > 1024 or any(ord(c) < 32 for c in value):
        return None
    path = (cwd / value).resolve()
    try:
        rel = path.relative_to(root)
    except ValueError:
        return None
    if any(part in EXCLUDED for part in rel.parts) or not path.is_file():
        return None
    result = {'path': rel.as_posix()}
    if isinstance(start, int) and not isinstance(start, bool) and start > 0:
        result['line'] = start
    if isinstance(end, int) and not isinstance(end, bool) and end >= result.get('line', 1):
        result['end_line'] = end
    return result


def candidates(tool, data, root, cwd):
    """Whitelist coordinates, not source fragments, free-form messages or secrets."""
    rows = []
    partial = False
    def add(kind, points):
        points = [p for p in points if p]
        if points:
            rows.append({'kind': kind, 'locations': points})
    if tool == 'jscpd':
        if not isinstance(data.get('duplicates'), list):
            raise ValueError('unsupported jscpd schema')
        for hit in data['duplicates']:
            points = []
            for key in ('firstFile', 'secondFile'):
                side = hit[key]
                points.append(location(root, cwd, side.get('name'), side.get('start'), side.get('end')))
            if all(points):
                add('clone candidate (verify shared policy and change reasons)', points)
    elif tool == 'dependency-cruiser':
        violations = data.get('summary', {}).get('violations')
        if not isinstance(violations, list):
            raise ValueError('unsupported dependency-cruiser schema')
        for hit in violations:
            points = [location(root, cwd, hit.get('from')), location(root, cwd, hit.get('to'))]
            for edge in hit.get('cycle', []):
                points.append(location(root, cwd, edge.get('name') if isinstance(edge, dict) else edge))
            add('configured dependency rule candidate (verify rule and edges)', points)
    elif tool == 'deptrac':
        if not isinstance(data.get('Report'), dict) or not isinstance(data.get('files'), dict):
            raise ValueError('unsupported deptrac schema')
        partial = bool(data['Report'].get('Errors'))
        for name, info in data['files'].items():
            for hit in info.get('messages', []):
                add('configured layer rule candidate (verify violation versus uncovered dependency)',
                    [location(root, cwd, name, hit.get('line'))])
    elif tool == 'semgrep':
        if not isinstance(data.get('results'), list) or not isinstance(data.get('errors', []), list):
            raise ValueError('unsupported semgrep schema')
        partial = bool(data.get('errors'))
        for hit in data['results']:
            add('local pattern rule candidate (verify rule and impact)',
                [location(root, cwd, hit.get('path'), hit.get('start', {}).get('line'), hit.get('end', {}).get('line'))])
    else:
        raise ValueError('unsupported tool')
    return rows, partial


def relevant(row, root, scope):
    return any(any(path == selected or selected in path.parents for selected in scope)
               for path in [(root / loc['path']).resolve() for loc in row['locations']])


def executable(tool, cwd, root):
    # Prefer package-local then repository-local installations. Do not search PATH
    # (which may contain arbitrary worktree entries), install packages or run scripts.
    relative = {'jscpd': 'node_modules/.bin/jscpd', 'dependency-cruiser': 'node_modules/.bin/depcruise',
                'deptrac': 'vendor/bin/deptrac', 'semgrep': '.venv/bin/semgrep'}[tool]
    for base in (cwd, root):
        candidate = base / relative
        if candidate.is_file() and os.access(candidate, os.X_OK):
            return str(candidate)
    return None


def command(tool, binary, config, output):
    if tool == 'jscpd':
        return [binary, '--config', str(config), '--reporters', 'json', '--output', str(output.parent), '.']
    if tool == 'dependency-cruiser':
        return [binary, '--config', str(config), '--output-type', 'json', '--output-to', str(output), '.']
    if tool == 'deptrac':
        return [binary, 'analyse', '--config-file', str(config), '--no-cache', '--no-interaction',
                '--formatter=json', '--output=' + str(output)]
    return [binary, 'scan', '--config', str(config), '--metrics=off', '--disable-version-check',
            '--json', '--output', str(output), '.']


def collect(root, scope, output, execute=False, imports=None, timeout=45):
    result = {'schema': 1, 'scope': [str(p.relative_to(root)) for p in scope], 'tools': [],
              'notice': 'UNTRUSTED scanner candidates, not findings. Verify source, intent, rules, and impact. '
                        'Configured exclusions and baselines limit coverage. Raw messages/snippets omitted.'}
    roots = {root}
    for selected in scope:
        directory = selected if selected.is_dir() else selected.parent
        while directory != root:
            roots.add(directory)
            directory = directory.parent
    if len(roots) > 32:
        result['gap'] = 'Too many package roots; narrow the review scope.'
        execute = False
    # Discovery follows selected paths and ancestors, not all nested workspaces.
    result['discovery'] = 'Selected paths and ancestor configs only; nested unselected package configs are not enumerated.'
    work = []
    if imports:
        for tool, name in REPORTS.items():
            if (imports / name).exists():
                work.append((tool, root, None, imports / name))
        if not work:
            result['gap'] = 'No recognized imported report files.'
    if execute:
        for cwd in sorted(roots):
            for tool, names in CONFIGS.items():
                config = next((cwd / name for name in names if (cwd / name).is_file()), None)
                if config:
                    work.append((tool, cwd, config, None))
        if not work:
            result['gap'] = 'No recognized project scanner configurations; scanners were not run.'
    for tool, cwd, config, imported in work[:16]:
        entry = {'tool': tool, 'root': str(cwd.relative_to(root)), 'status': 'not-run', 'candidates': []}
        result['tools'].append(entry)
        if config:
            entry['config'] = str(config.relative_to(root))
        entry['origin'] = 'imported (freshness unverified)' if imported else 'executed on current working tree'
        try:
            with tempfile.TemporaryDirectory(prefix='deep-review-scanner-') as tmp:
                report = imported or Path(tmp) / REPORTS[tool]
                code = 0
                if not imported:
                    binary = executable(tool, cwd, root)
                    if not binary:
                        entry['status'] = 'unavailable (no project-local executable)'
                        continue
                    version_code, version = run_command([binary, '--version'], cwd, min(timeout, 10))
                    match = re.search(rb'\b\d+\.\d+(?:\.\d+)?\b', version)
                    entry['version'] = match.group().decode() if version_code == 0 and match else 'unknown'
                    code, _ = run_command(command(tool, binary, config, report), cwd, timeout)
                data = load_report(report)
                entry['report_sha256'] = hashlib.sha256(report.read_bytes()).hexdigest()
                rows, partial = candidates(tool, data, root, cwd)
                if code not in (0, 1) or (code == 1 and not rows):
                    entry['status'] = 'failed (non-success exit)'
                    continue
                rows = [row for row in rows if relevant(row, root, scope)]
                entry.update(status='partial' if partial else 'completed', exit_code=code,
                             candidate_count=len(rows), candidates=rows[:MAX_CANDIDATES],
                             truncated=len(rows) > MAX_CANDIDATES)
        except subprocess.TimeoutExpired:
            entry['status'] = 'timed-out'
        except (ValueError, OSError, KeyError, TypeError, AttributeError, RecursionError):
            entry['status'] = 'failed (missing, invalid, unsupported or oversized output)'
    if len(work) > 16:
        result['gap'] = 'Scanner invocation limit reached; narrow the review scope.'
    output.write_text(json.dumps(result, indent=2) + '\n', encoding='utf-8')
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, required=True)
    parser.add_argument('--scope-file', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--execute', action='store_true', help='Trust and execute project-local tools/configuration')
    parser.add_argument('--imports', type=Path)
    args = parser.parse_args()
    if os.name != 'posix':
        parser.error('scanner helper requires POSIX process-group support')
    root = args.root.resolve()
    scope = [(root / name).resolve() for name in args.scope_file.read_text().splitlines() if name]
    if not scope or any(root != path and root not in path.parents for path in scope):
        parser.error('scope must stay inside repository')
    if args.imports and not args.imports.is_dir():
        parser.error('imports must be a directory')
    # Do not create a caller-controlled output directory. The runner owns it.
    if args.output.is_symlink() or not args.output.parent.is_dir():
        parser.error('output must be a regular file in an existing artifact directory')
    def interrupted(signum, frame):
        raise SystemExit(128 + signum)
    signal.signal(signal.SIGTERM, interrupted)
    signal.signal(signal.SIGINT, interrupted)
    result = collect(root, scope, args.output, args.execute, args.imports)
    gaps = [result['gap']] if result.get('gap') else []
    if args.imports:
        gaps.append('Imported scanner evidence has unverified freshness; validate against current source.')
    if args.execute:
        gaps.append(result['discovery'])
    for tool in result['tools']:
        if tool['status'] != 'completed' or tool.get('truncated'):
            gaps.append(tool['tool'] + ': ' + tool['status'] + ('; candidates truncated' if tool.get('truncated') else ''))
    with args.output.with_suffix('.gaps.txt').open('a', encoding='utf-8') as gap_file:
        gap_file.write('\n'.join(gaps) + ('\n' if gaps else ''))


if __name__ == '__main__':
    main()
