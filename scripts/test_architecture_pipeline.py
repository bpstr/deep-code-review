"""Fake-provider runner contracts; model behavior is evaluated by opt-in fixtures."""
from pathlib import Path
import os
import re
import shutil
import subprocess
import tempfile
import unittest
ROOT = Path(__file__).resolve().parents[1]
FAKE = r'''#!/usr/bin/env python3
import os,re,sys
from pathlib import Path
p=sys.argv[-1]
def target(pattern):
    m=re.search(pattern,p)
    assert m,p
    return Path(m.group(1))
def log(s):
    with open(os.environ['FAKE_LOG'],'a') as f:f.write(s+'\n')
if p.startswith('Read stack profiling instructions from:'):
    assert 'architecture-context.md' in p
    target(r'Write the shared profile to: (.+)').write_text('# Stack\nArchitecture Context: documented policy ownership.\n')
    log('stack')
elif 'specialized READ-ONLY' in p:
    name=re.search(r'analysis instructions from: .*/([^/]+)\.md',p).group(1)
    assert 'architecture-review.md' in p and 'architecture-evidence.json' in p
    target(r'Write your complete Markdown findings to: (.+)').write_text('Reviewed: '+name+'\n')
    log('agent:'+name)
elif 'synthesis agent for' in p:
    assert 'confirmed maintainability improvements' in p
    target(r'write the merged report to: (.+)').write_text('Duplicated policy: a.py:1; b.py:1.\nStyle-only fan-in.\n')
    log('synthesis')
elif 'extract every distinct' in p:
    assert 'trade-off and validation' in p
    d=target(r'write (.+)/finding-N.md');d.mkdir(exist_ok=True)
    (d/'finding-1.md').write_text('TITLE: Shared policy duplication\nSEVERITY: MEDIUM\nLOCATION: a.py:1; b.py:1\n')
    (d/'finding-2.md').write_text('TITLE: High fan-in alone\nSEVERITY: LOW\n')
    (d/'count.txt').write_text('2');log('extract')
elif 'confidence scorer for a batch' in p:
    assert 'Do not mix them' in target(r'Read validation policy from: (.+)').read_text()
    assert 'independent of severity' in p and 'plausible minor' not in p
    d=target(r'Score batch marker: (.+)/score-batch-')
    for n in re.search(r'Batch findings:([^\n]+)',p).group(1).split():
        (d/f'score-{n}.txt').write_text('SCORE: '+('95' if n=='1' else '5')+'\nREASON: Independent evidence.\n')
    log('score')
elif 'final code-review triage editor' in p:
    assert 'Do not promote P2 debt' in p
    d=target(r'Read: (.+)/REPORT.md')
    threshold=int(re.search(r'below (\d+)',p).group(1))
    score=int(re.search(r'SCORE: (\d+)',(d/'findings/score-1.txt').read_text()).group(1))
    text='## P2 Worth noting\nShared policy duplication: a.py:1; b.py:1. Preserve domain boundaries.\n' if score>=threshold else 'No findings.\n'
    target(r'Write the final report to: (.+)').write_text(text);log('final')
else:raise RuntimeError('Unexpected stage')
'''

class PipelineTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='architecture-pipeline-')
        self.base = Path(self.tmp.name)
        self.skill = self.base / 'skill'
        shutil.copytree(ROOT / 'skills/deep-review', self.skill, ignore=shutil.ignore_patterns('__pycache__'))
        # Non-architecture definitions are immaterial to this contract test.
        paths = ['support/stack-profiler.md'] + ['agents/'+n+'.md' for n in
                 ['code-reviewer','silent-failure-hunter','synthesizer','comment-analyzer','test-analyzer',
                  'accessibility-scanner','localization-scanner','concurrency-analyzer','performance-analyzer',
                  'security-reviewer','pii-leak-scanner','agent-instructions-reviewer','guidelines-reviewer',
                  'git-history-reviewer','prior-feedback-reviewer']]
        for name in paths:
            path = self.skill / name
            if not path.exists(): path.write_text('# Mocked non-architecture definition\n')
        self.repo = self.base / 'repo'; self.repo.mkdir()
        for name in ['a.py','b.py']: (self.repo / name).write_text('pass\n')
        subprocess.run(['git','init','-q','-b','main'], cwd=self.repo, check=True)
        subprocess.run(['git','add','.'], cwd=self.repo, check=True)
        subprocess.run(['git','-c','user.name=Fixture','-c','user.email=fixture@example.invalid',
                        'commit','-qm','fixture'], cwd=self.repo, check=True)
        bindir=self.base/'bin';bindir.mkdir()
        (bindir/'codex').write_text(FAKE);(bindir/'codex').chmod(0o755)
        self.log=self.base/'calls'
        self.env=dict(os.environ,PATH=str(bindir)+os.pathsep+os.environ['PATH'],
                      TMPDIR=str(self.base),FAKE_LOG=str(self.log),CONFIDENCE_THRESHOLD='80')
        self.env.pop('DEEP_REVIEW_AUTO_SPECIALISTS',None)
        self.env.pop('DEEP_REVIEW_PERSISTENT_RUN_DIR',None)

    def tearDown(self): self.tmp.cleanup()

    def run_review(self,*args):
        self.log.write_text('')
        proc=subprocess.run(['bash',str(self.skill/'scripts/deep-review-engine.sh'),'--provider','codex',
                             '--max-concurrent','2','--keep-results',*args],cwd=self.repo,env=self.env,
                            capture_output=True,text=True,timeout=25)
        self.assertEqual(proc.returncode,0,proc.stderr+proc.stdout)
        artifacts=Path(re.search(r'Review directory: (.+)',proc.stderr).group(1))
        self.assertEqual(proc.stdout,(artifacts/'FINAL.md').read_text())
        return proc,self.log.read_text().splitlines()

    def test_arch_routes_seven_and_profiles_once(self):
        proc,calls=self.run_review('.','arch')
        self.assertEqual(calls.count('stack'),1)
        self.assertEqual({c.split(':',1)[1] for c in calls if c.startswith('agent:')},
                         {'dependency-mapper','cycle-detector','hotspot-analyzer','pattern-scout',
                          'scale-assessor','code-simplifier','type-design-analyzer'})
        self.assertIn('P2 Worth noting',proc.stdout)
        self.assertIn('a.py:1; b.py:1',proc.stdout)
        self.assertNotIn('fan-in',proc.stdout)

    def test_core_compatibility(self):
        _,calls=self.run_review('.','core')
        self.assertNotIn('stack',calls)
        self.assertEqual(sum(c.startswith('agent:') for c in calls),7)
        self.assertNotIn('agent:code-simplifier',calls)

    def test_exact_full_compatibility(self):
        _,calls=self.run_review('--no-auto-specialists','.','full')
        self.assertNotIn('stack',calls)
        self.assertIn('agent:code-simplifier',calls)

    def test_full_deduplicates_reviewers(self):
        _,calls=self.run_review('.','full','arch','simplify','types')
        self.assertEqual(calls.count('stack'),1)
        self.assertEqual(calls.count('agent:code-simplifier'),1)
        self.assertEqual(calls.count('agent:type-design-analyzer'),1)

    def test_missing_tool_gap_persisted(self):
        (self.repo/'.jscpd.json').write_text('{}')
        proc,_=self.run_review('--architecture-tools','.','arch')
        self.assertIn('Scanner coverage notes:',proc.stdout)
        self.assertIn('unavailable',proc.stdout)

    def test_import_freshness_reported(self):
        reports=self.base/'reports with spaces';reports.mkdir()
        (reports/'jscpd-report.json').write_text('{"duplicates": []}')
        proc,_=self.run_review('--architecture-evidence='+str(reports),'.','arch')
        self.assertIn('unverified freshness',proc.stdout)

    def cache(self):
        run=self.base/'state'
        (run/'checkpoints/data').mkdir(parents=True)
        (run/'checkpoints/complete').mkdir()
        self.env['DEEP_REVIEW_PERSISTENT_RUN_DIR']=str(run)
        return run/'checkpoints/data/sentinel'

    def test_prompt_change_invalidates_checkpoints(self):
        marker=self.cache()
        self.run_review('.','arch');marker.write_text('retained')
        self.run_review('.','arch');self.assertTrue(marker.exists())
        with (self.skill/'support/architecture-review.md').open('a') as f:f.write('\nChanged policy.\n')
        self.run_review('.','arch');self.assertFalse(marker.exists())

    def test_import_bytes_invalidate_checkpoints(self):
        marker=self.cache()
        reports=self.base/'reports';reports.mkdir()
        report=reports/'jscpd-report.json';report.write_text('{"duplicates": []}')
        args=('--architecture-evidence='+str(reports),'.','arch')
        self.run_review(*args);marker.write_text('stale')
        report.write_text('{"duplicates": [], "statistics": {"changed": true}}')
        self.run_review(*args);self.assertFalse(marker.exists())

if __name__=='__main__':unittest.main()
