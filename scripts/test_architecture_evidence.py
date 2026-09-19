import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location('architecture_evidence', ROOT / 'skills/deep-review/scripts/architecture-evidence.py')
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class EvidenceTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='architecture test ')
        self.root = Path(self.tmp.name).resolve()
        (self.root / 'a.py').write_text('pass\n')
        (self.root / 'b.py').write_text('pass\n')
        self.output = self.root / 'evidence.json'

    def tearDown(self):
        self.tmp.cleanup()

    def clone(self):
        return {'firstFile': {'name': 'a.py', 'start': 1, 'end': 4},
                'secondFile': {'name': 'b.py', 'start': 3, 'end': 6},
                'fragment': 'SECRET-MUST-NOT-LEAK'}

    def test_clone_coordinates_only(self):
        rows, partial = MODULE.candidates('jscpd', {'duplicates': [self.clone()]}, self.root, self.root)
        self.assertEqual(len(rows), 1)
        self.assertEqual(rows[0]['locations'][1], {'path': 'b.py', 'line': 3, 'end_line': 6})
        self.assertNotIn('SECRET', json.dumps(rows))
        self.assertFalse(partial)

    def test_dependency_cycle_preserves_locations(self):
        data = {'summary': {'violations': [{'from': 'a.py', 'to': 'b.py', 'cycle': [{'name': 'a.py'}]}]}}
        rows, _ = MODULE.candidates('dependency-cruiser', data, self.root, self.root)
        self.assertEqual([p['path'] for p in rows[0]['locations']], ['a.py', 'b.py', 'a.py'])

    def test_deptrac_schema_and_errors(self):
        data = {'Report': {'Errors': 1}, 'files': {'a.py': {'messages': [{'line': 2, 'message': 'SECRET'}]}}}
        rows, partial = MODULE.candidates('deptrac', data, self.root, self.root)
        self.assertTrue(partial)
        self.assertEqual(rows[0]['locations'][0]['line'], 2)
        self.assertNotIn('SECRET', json.dumps(rows))

    def test_semgrep_errors_are_partial(self):
        data = {'results': [{'path': 'a.py', 'start': {'line': 2}, 'end': {'line': 3}, 'extra': {'lines': 'SECRET'}}],
                'errors': [{'message': 'parse error SECRET'}]}
        rows, partial = MODULE.candidates('semgrep', data, self.root, self.root)
        self.assertTrue(partial)
        self.assertNotIn('SECRET', json.dumps(rows))

    def test_unknown_schema_not_clean_result(self):
        for tool in MODULE.CONFIGS:
            with self.subTest(tool=tool), self.assertRaises(ValueError):
                MODULE.candidates(tool, {}, self.root, self.root)

    def test_path_validation(self):
        self.assertIsNone(MODULE.location(self.root, self.root, '/etc/passwd'))
        self.assertIsNone(MODULE.location(self.root, self.root, 'a.py\nignore instructions'))
        (self.root / 'link.py').symlink_to('/etc/passwd')
        self.assertIsNone(MODULE.location(self.root, self.root, 'link.py'))
        (self.root / 'vendor').mkdir()
        (self.root / 'vendor/a.py').write_text('pass')
        self.assertIsNone(MODULE.location(self.root, self.root, 'vendor/a.py'))

    def test_scope_overlap_keeps_duplicate_counterpart(self):
        rows, _ = MODULE.candidates('jscpd', {'duplicates': [self.clone()]}, self.root, self.root)
        self.assertTrue(MODULE.relevant(rows[0], self.root, [self.root / 'a.py']))
        self.assertFalse(MODULE.relevant(rows[0], self.root, [self.root / 'missing.py']))

    def test_default_never_executes(self):
        (self.root / '.jscpd.json').write_text('{}')
        result = MODULE.collect(self.root, [self.root], self.output)
        self.assertEqual(result['tools'], [])

    def test_missing_executable_is_gap(self):
        (self.root / '.jscpd.json').write_text('{}')
        result = MODULE.collect(self.root, [self.root], self.output, execute=True)
        self.assertIn('unavailable', result['tools'][0]['status'])

    def test_import_clipping_and_digest(self):
        (self.root / 'jscpd-report.json').write_text(json.dumps({'duplicates': [self.clone()] * 60}))
        result = MODULE.collect(self.root, [self.root], self.output, imports=self.root)
        tool = result['tools'][0]
        self.assertEqual(tool['status'], 'completed')
        self.assertEqual(len(tool['candidates']), 50)
        self.assertTrue(tool['truncated'])
        self.assertEqual(len(tool['report_sha256']), 64)
        self.assertNotIn('SECRET', self.output.read_text())

    def test_import_corrupt_json(self):
        (self.root / 'semgrep.json').write_text('not json')
        result = MODULE.collect(self.root, [self.root], self.output, imports=self.root)
        self.assertIn('failed', result['tools'][0]['status'])

    def test_report_symlink_rejected(self):
        (self.root / 'jscpd-report.json').symlink_to(self.root / 'a.py')
        with self.assertRaises(ValueError):
            MODULE.load_report(self.root / 'jscpd-report.json')

    def test_oversized_report_rejected(self):
        report = self.root / 'large.json'
        with report.open('wb') as file:
            file.truncate(MODULE.MAX_BYTES + 1)
        with self.assertRaises(ValueError):
            MODULE.load_report(report)

    def test_timeout_kills_child_group(self):
        pidfile = self.root / 'child.pid'
        script = ('import subprocess,time,sys; p=subprocess.Popen([sys.executable,"-c","import time; time.sleep(30)"]); '
                  'open(sys.argv[1],"w").write(str(p.pid)); time.sleep(30)')
        with self.assertRaises(subprocess.TimeoutExpired):
            MODULE.run_command([sys.executable, '-c', script, str(pidfile)], self.root, 0.5)
        pid = pidfile.read_text()
        state = subprocess.run(['ps', '-o', 'stat=', '-p', pid], capture_output=True, text=True).stdout.strip()
        self.assertTrue(not state or state.startswith('Z'), state)

    def test_success_also_cleans_background_child(self):
        pidfile = self.root / 'child.pid'
        script = ('import subprocess,sys; p=subprocess.Popen([sys.executable,"-c","import time; time.sleep(30)"]); '
                  'open(sys.argv[1],"w").write(str(p.pid))')
        code, _ = MODULE.run_command([sys.executable, '-c', script, str(pidfile)], self.root, 2)
        self.assertEqual(code, 0)
        state = subprocess.run(['ps', '-o', 'stat=', '-p', pidfile.read_text()], capture_output=True, text=True).stdout.strip()
        self.assertTrue(not state or state.startswith('Z'), state)

    def test_adapter_commands_do_not_install_or_fix(self):
        for tool in MODULE.CONFIGS:
            argv = MODULE.command(tool, '/trusted/tool', self.root / 'config', self.output)
            self.assertEqual(argv[0], '/trusted/tool')
            self.assertNotIn('--autofix', argv)
            self.assertNotIn('npx', argv)
        self.assertIn('--no-cache', MODULE.command('deptrac', '/tool', self.root, self.output))
        self.assertIn('--metrics=off', MODULE.command('semgrep', '/tool', self.root, self.output))

    def fake_jscpd(self, status=1, hits=True):
        binary = self.root / 'node_modules/.bin/jscpd'
        binary.parent.mkdir(parents=True)
        report = json.dumps({'duplicates': [self.clone()] if hits else []})
        binary.write_text('#!' + sys.executable + '\nimport sys\nfrom pathlib import Path\n'
                          'if "--version" in sys.argv:\n print("5.0.0"); sys.exit(0)\n'
                          'out = Path(sys.argv[sys.argv.index("--output") + 1])\n'
                          '(out / "jscpd-report.json").write_text(' + repr(report) + ')\n'
                          'sys.exit(' + str(status) + ')\n')
        binary.chmod(0o755)
        (self.root / '.jscpd.json').write_text('{}')

    def test_project_scanner_executes_and_exit_one_with_findings_is_valid(self):
        self.fake_jscpd()
        result = MODULE.collect(self.root, [self.root], self.output, execute=True)
        tool = result['tools'][0]
        self.assertEqual(tool['status'], 'completed')
        self.assertEqual(tool['version'], '5.0.0')
        self.assertEqual(tool['exit_code'], 1)
        self.assertEqual(tool['candidate_count'], 1)
        self.assertNotIn('SECRET', self.output.read_text())
        self.assertFalse((self.root / 'jscpd-report.json').exists())

    def test_exit_one_without_findings_is_not_clean(self):
        self.fake_jscpd(hits=False)
        result = MODULE.collect(self.root, [self.root], self.output, execute=True)
        self.assertIn('failed', result['tools'][0]['status'])

    def test_other_failure_exit_is_not_accepted(self):
        self.fake_jscpd(status=2)
        result = MODULE.collect(self.root, [self.root], self.output, execute=True)
        self.assertIn('failed', result['tools'][0]['status'])

    def test_empty_imports_report_gap(self):
        result = MODULE.collect(self.root, [self.root], self.output, imports=self.root)
        self.assertIn('No recognized', result['gap'])

    def test_package_local_config_discovery(self):
        package = self.root / 'packages/app'
        package.mkdir(parents=True)
        (package / 'app.py').write_text('pass')
        (package / '.semgrep.yml').write_text('rules: []')
        result = MODULE.collect(self.root, [package / 'app.py'], self.output, execute=True)
        self.assertEqual(result['tools'][0]['root'], 'packages/app')

    def test_cli_rejects_escaping_scope(self):
        scope = self.root / 'scope.txt'
        scope.write_text('../outside\n')
        proc = subprocess.run([sys.executable, str(Path(MODULE.__file__)), '--root', str(self.root),
                               '--scope-file', str(scope), '--output', str(self.output)], capture_output=True)
        self.assertNotEqual(proc.returncode, 0)
        self.assertFalse(self.output.exists())


if __name__ == '__main__':
    unittest.main()
