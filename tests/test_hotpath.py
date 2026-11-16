"""Synthetic checks for conservative batch paths and fallback semantics."""
import os
import shutil
import threading
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[1]
CLI = ROOT / 'bin/letterbox'
HELPER = ROOT / 'lib/fast/fastpath.py'
ID = '2020-01-01T120000-alpha-request-one-1234abcd'


class HotPathTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.work = Path(self.temp.name).resolve()
        self.box = self.work / 'box'
        for seat in ('alpha', 'beta'):
            for folder in ('inbox', 'processed'):
                (self.box / seat / folder).mkdir(parents=True)
        self.letter = self.box / 'beta' / 'inbox' / (ID + '.md')
        self.write(self.letter, ID)
        self.env = dict(os.environ, LETTERBOX_DIR=str(self.box), LETTERBOX_AGENT='alpha',
                        LETTERBOX_DOORBELL='/nonexistent-test-adapter',
                        LETTERBOX_CHECK_STALE_DAYS='99999', LC_ALL='C')

    def write(self, path, ident, *, closed=True):
        path.write_text('---\nid: ' + ident + '\nfrom: alpha\nto: beta\ntype: request\n'
                        'requires_ack: true\n' + ('---\n' if closed else '') + 'body\n')

    def run_cli(self, *args, env=None):
        return subprocess.run([str(CLI), *args], env=env or self.env, capture_output=True, text=True, timeout=20)

    def helper(self, *args):
        return subprocess.run([sys.executable, '-I', '-B', str(HELPER), *map(str, args)],
                              env=self.env, capture_output=True, text=True, timeout=20)

    def test_check_fast_matches_output_with_ack_progress(self):
        (Path(str(self.letter) + '.ack')).write_text('acked_at: 2020-01-01T12:00:00Z\nprogress: working\nprogress_at: 2020-01-01T12:00:00Z\n')
        cli = self.run_cli('check', 'beta')
        fast = self.helper('check', self.letter.parent, 'beta', str(int(time.time())), str(99999*86400), '99999', 'false')
        self.assertEqual((cli.returncode, cli.stderr), (0, ''))
        self.assertEqual(fast.returncode, 0)
        self.assertEqual(fast.stdout, cli.stdout)
        self.assertIn('[ACCEPTED]', cli.stdout)
        self.assertIn('progress: working', cli.stdout)

    def test_exact_lookup_uses_header_not_filename_and_preserves_ambiguity(self):
        alias = self.letter.with_name('alias.md')
        self.letter.rename(alias)
        fast = self.helper('resolve', self.box, ID)
        self.assertEqual((fast.returncode, fast.stdout.strip()), (0, str(alias)))
        self.assertEqual(self.run_cli('nudge', ID).returncode, 0)
        duplicate = self.box / 'alpha' / 'processed' / 'copy.md'
        self.write(duplicate, ID)
        self.assertNotEqual(self.helper('resolve', self.box, ID).returncode, 0)
        result = self.run_cli('nudge', ID)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('ambiguous', result.stderr)

    def test_exact_lookup_treats_glob_characters_in_root_as_literal(self):
        literal = self.work / 'box[1]'
        decoy = self.work / 'box1'
        self.box.rename(literal)
        for folder in ('inbox', 'processed'):
            (decoy / 'beta' / folder).mkdir(parents=True)
        self.write(decoy / 'beta' / 'inbox' / 'decoy.md', ID)
        actual = literal / 'beta' / 'inbox' / (ID + '.md')
        result = self.helper('resolve', literal, ID)
        self.assertEqual((result.returncode, result.stdout.strip()), (0, str(actual)))

    def test_malformed_body_id_cannot_create_match(self):
        self.letter.unlink()
        self.write(self.box / 'beta' / 'inbox' / 'bad.md', ID, closed=False)
        self.assertNotEqual(self.helper('resolve', self.box, ID).returncode, 0)
        result = self.run_cli('nudge', ID)
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn('doorbell-outcome', result.stdout)

    def test_control_progress_falls_back_and_is_sanitized(self):
        Path(str(self.letter) + '.ack').write_bytes(b'progress: bad\x1b[31m\n')
        self.assertNotEqual(self.helper('check', self.letter.parent, 'beta', str(int(time.time())), str(99999*86400), '99999', 'false').returncode, 0)
        result = self.run_cli('check', 'beta')
        self.assertEqual(result.returncode, 0)
        self.assertNotIn('\x1b', result.stdout)
        self.assertIn('progress: bad[31m', result.stdout)

    def test_stale_order_and_recent_view(self):
        older = self.box / 'beta' / 'inbox' / 'old.md'
        old_id = '2019-01-01T120000-alpha-request-old-deadbeef'
        self.write(older, old_id)
        env = dict(self.env, LETTERBOX_CHECK_STALE_DAYS='14')
        result = self.run_cli('check', 'beta', env=env)
        self.assertEqual(result.returncode, 0)
        self.assertIn('0 live · 2 stale', result.stdout)
        self.assertLess(result.stdout.index('1234abcd'), result.stdout.index('deadbeef'))
        recent = self.run_cli('check', 'beta', '--recent', env=env)
        self.assertEqual(recent.returncode, 0)
        self.assertIn('2 stale items hidden', recent.stdout)
        self.assertNotIn('1234abcd', recent.stdout)

    def test_unicode_sender_batch_and_orphan_sidecar_fallback(self):
        self.letter.write_text(self.letter.read_text().replace('from: alpha', 'from: café'))
        direct = self.helper('check', self.letter.parent, 'beta', str(int(time.time())), str(99999*86400), '99999', 'false')
        self.assertEqual(direct.returncode, 0)
        output = self.run_cli('check', 'beta')
        self.assertEqual((direct.stdout, direct.stderr), (output.stdout, output.stderr))
        self.assertEqual(output.returncode, 0)
        self.assertIn('from: café', output.stdout)
        bindir = self.work / 'no-unicode-python'; bindir.mkdir()
        python = bindir / 'python3'; python.write_text('#!/bin/sh\nexit 127\n'); python.chmod(0o755)
        env = dict(self.env, PATH=str(bindir) + os.pathsep + self.env['PATH'])
        shell = self.run_cli('check', 'beta', env=env)
        self.assertEqual((output.returncode, output.stdout, output.stderr), (shell.returncode, shell.stdout, shell.stderr))
        orphan = self.letter.parent / 'orphan.md.ack'
        orphan.write_text('acked_at: 2020-01-01T12:00:00Z\n')
        output = self.run_cli('check', 'beta')
        self.assertIn('orphan ACK sidecar', output.stderr)

    def test_exact_lookup_matches_legacy_colonless_id_field(self):
        self.letter.unlink()
        path = self.box / 'beta' / 'inbox' / 'legacy.md'
        path.write_text('---\nid\nfrom: alpha\nto: beta\ntype: request\n---\n')
        fast = self.helper('resolve', self.box, 'id')
        self.assertEqual((fast.returncode, fast.stdout.strip()), (0, str(path)))
        self.assertEqual(self.run_cli('nudge', 'id').returncode, 0)

    def test_malformed_file_is_rendered_without_disabling_batch(self):
        bad = self.letter.parent / 'empty.md'
        bad.write_bytes(b'')
        fast = self.helper('check', self.letter.parent, 'beta', str(int(time.time())), str(99999*86400), '99999', 'false')
        self.assertEqual(fast.returncode, 0)
        self.assertIn('═══ MALFORMED  empty.md', fast.stdout)
        self.assertIn('letterbox: MALFORMED ' + str(bad), fast.stderr)
        bindir = self.work / 'bin'; bindir.mkdir()
        python = bindir / 'python3'; python.write_text('#!/bin/sh\nexit 127\n'); python.chmod(0o755)
        env = dict(self.env, PATH=str(bindir) + os.pathsep + self.env['PATH'])
        baseline = self.run_cli('check', 'beta', env=env)
        actual = self.run_cli('check', 'beta')
        self.assertEqual((actual.returncode, actual.stdout, actual.stderr), (baseline.returncode, baseline.stdout, baseline.stderr))

    def test_token_lookup_is_scoped_and_detects_collisions(self):
        self.assertEqual(self.helper('resolve', self.box, '1234abcd', 'owned-inbox', 'beta').stdout.strip(), str(self.letter))
        self.assertNotEqual(self.helper('resolve', self.box, '1234abcd', 'owned-inbox', 'alpha').returncode, 0)
        copy = self.box / 'alpha' / 'processed' / 'copy.md'
        self.write(copy, '2021-01-01T120000-alpha-info-copy-1234abcd')
        self.assertNotEqual(self.helper('resolve', self.box, '1234abcd', 'nudge', 'alpha').returncode, 0)
        self.assertEqual(self.helper('resolve', self.box, '1234abcd', 'owned-inbox', 'beta').stdout.strip(), str(self.letter))
        self.assertIn('ambiguous', self.run_cli('nudge', '1234abcd').stderr)

    def race_copy(self):
        copy = self.work / 'race-copy'
        for name in ('bin', 'lib'):
            shutil.copytree(ROOT / name, copy / name)
        helper = copy / 'lib/fast/fastpath.py'
        source = helper.read_text()
        needle = '    entries = list(os.scandir(inbox))\n'
        inject = """    entries = list(os.scandir(inbox))
    with open(os.environ['RACE_MARKER'], 'a') as marker:
        marker.write('pass\\n')
    os.unlink(os.environ['RACE_REMOVE'])
    with open(os.environ['RACE_ADD'], 'w') as added:
        added.write('---\\nid: 2021-01-01T120000-alpha-info-added-fedcba98\\nfrom: alpha\\nto: beta\\ntype: info\\nrequires_ack: false\\n---\\nbody\\n')
"""
        self.assertEqual(source.count(needle), 1)
        helper.write_text(source.replace(needle, inject))
        env = dict(self.env, RACE_MARKER=str(self.work / 'passes'), RACE_REMOVE=str(self.letter), RACE_ADD=str(self.letter.parent / 'added.md'))
        return copy, env

    def test_race_abort_emits_no_partial_output(self):
        copy, env = self.race_copy()
        (self.letter.parent / 'early-malformed.md').write_bytes(b'')
        result = subprocess.run([sys.executable, '-I', '-B', str(copy / 'lib/fast/fastpath.py'), 'check', str(self.letter.parent), 'beta', str(int(time.time())), str(99999*86400), '99999', 'false'], env=env, capture_output=True, timeout=20)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual((result.stdout, result.stderr), (b'', b''))

    def test_race_restart_matches_fresh_shell_check(self):
        copy, env = self.race_copy()
        command = [str(copy / 'bin/letterbox'), 'check', 'beta']
        result = subprocess.run(command, env=env, capture_output=True, timeout=20)
        bindir = self.work / 'no-python'; bindir.mkdir()
        python = bindir / 'python3'; python.write_text('#!/bin/sh\nexit 127\n'); python.chmod(0o755)
        shell_env = dict(self.env, PATH=str(bindir) + os.pathsep + self.env['PATH'])
        fresh = self.run_cli('check', 'beta', env=shell_env)
        self.assertEqual((result.returncode, result.stdout.decode(), result.stderr.decode()), (fresh.returncode, fresh.stdout, fresh.stderr))
        self.assertIn('fedcba98', fresh.stdout)
        self.assertNotIn('1234abcd', fresh.stdout)

    def test_race_restart_is_bounded_during_churn(self):
        copy, env = self.race_copy()
        stop = threading.Event()
        churn = self.letter.parent / 'churn.md'
        def writer():
            while not stop.is_set():
                try:
                    churn.write_text('---\n')
                    churn.unlink(missing_ok=True)
                except OSError:
                    pass
        thread = threading.Thread(target=writer)
        thread.start()
        try:
            result = subprocess.run([str(copy / 'bin/letterbox'), 'check', 'beta'], env=env, capture_output=True, timeout=20)
        finally:
            stop.set(); thread.join()
        self.assertEqual(result.returncode, 0)
        self.assertEqual((self.work / 'passes').read_text(), 'pass\n')

    def test_non_utf8_output_encoding_falls_back_before_output(self):
        program = ("import runpy,sys; sys.stdout.reconfigure(encoding='ascii'); "
                   "sys.argv=[sys.argv[1], 'check', *sys.argv[2:]]; runpy.run_path(sys.argv[0], run_name='__main__')")
        args = [sys.executable, '-I', '-B', '-c', program, str(HELPER), str(self.letter.parent), 'beta', str(int(time.time())), str(99999*86400), '99999', 'false']
        result = subprocess.run(args, env=self.env, capture_output=True, timeout=20)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual((result.stdout, result.stderr), (b'', b''))

    def test_missing_helper_falls_back_without_python_error(self):
        copy = self.work / 'without-helper'
        shutil.copytree(ROOT / 'bin', copy / 'bin')
        result = subprocess.run([str(copy / 'bin/letterbox'), 'check', 'beta'], env=self.env, capture_output=True, text=True, timeout=20)
        expected = self.run_cli('check', 'beta')
        self.assertEqual((result.returncode, result.stdout, result.stderr), (expected.returncode, expected.stdout, expected.stderr))
        self.assertEqual(result.stderr, '')

    def test_no_python_falls_back(self):
        expected = self.run_cli('check', 'beta')
        bindir = self.work / 'bin'; bindir.mkdir()
        python = bindir / 'python3'; python.write_text('#!/bin/sh\nexit 127\n'); python.chmod(0o755)
        env = dict(self.env, PATH=str(bindir) + os.pathsep + self.env['PATH'])
        fallback = self.run_cli('check', 'beta', env=env)
        self.assertEqual((expected.returncode, expected.stdout, expected.stderr),
                         (fallback.returncode, fallback.stdout, fallback.stderr))


if __name__ == '__main__':
    unittest.main(verbosity=2)
