"""Deterministic post-read/pre-relist mutations in synthetic stores only."""
import contextlib
import io
import json
import os
from pathlib import Path
import runpy
import stat
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'lib/query'))
import query
import scanner

LETTER = b'---\nid: existing\nfrom: alpha\nto: beta\ntype: request\n---\nbody\n'


class ListingBoundary(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.box = Path(self.temp.name).resolve() / 'store'
        for folder in ('inbox', 'processed'):
            (self.box / 'beta' / folder).mkdir(parents=True)
        (self.box / 'beta' / 'inbox' / 'existing.md').write_bytes(LETTER)

    def check_mutation(self, mode, mutation):
        fired = []
        def hook(fd, ref):
            if ref != 'beta/inbox':
                return
            fired.append(ref)
            if mutation == 'add':
                f = os.open('new.md', os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600, dir_fd=fd)
                os.close(f)
            elif mutation == 'remove':
                os.unlink('existing.md', dir_fd=fd)
            elif mutation == 'replace':
                f = os.open('replacement.tmp', os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600, dir_fd=fd)
                os.write(f, LETTER.replace(b'body', b'changed-body'))
                os.close(f)
                os.rename('replacement.tmp', 'existing.md', src_dir_fd=fd, dst_dir_fd=fd)
            elif mutation == 'rewrite_masked':
                f = os.open('existing.md', os.O_RDWR, dir_fd=fd)
                try:
                    os.pwrite(f, LETTER.replace(b'alpha', b'gamma'), 0)
                finally:
                    os.close(f)
            elif mutation == 'rewrite':
                f = os.open('existing.md', os.O_RDWR, dir_fd=fd)
                try:
                    before = os.fstat(f)
                    os.pwrite(f, LETTER.replace(b'alpha', b'gamma'), 0)
                    # Force a distinct leaf timestamp independent of filesystem ticks.
                    os.utime(f, ns=(before.st_atime_ns, before.st_mtime_ns - 2_000_000_000))
                finally:
                    os.close(f)
            elif mutation == 'transient':
                f = os.open('temporary.tmp', os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600, dir_fd=fd)
                os.close(f)
                os.unlink('temporary.tmp', dir_fd=fd)
            else:
                raise AssertionError(mutation)

        # Model a coarse filesystem: directory stat snapshots cannot reveal
        # changes. Names and leaf identity checks must carry the test.
        real_fstat, real_stat = os.fstat, os.stat
        directories = {}
        leaf = real_stat(self.box / 'beta' / 'inbox' / 'existing.md')
        leaf_id = (leaf.st_dev, leaf.st_ino)
        def frozen_directory_fstat(fd):
            info = real_fstat(fd)
            if stat.S_ISDIR(info.st_mode):
                return directories.setdefault((info.st_dev, info.st_ino), info)
            if mutation == 'rewrite_masked' and (info.st_dev, info.st_ino) == leaf_id:
                return leaf
            return info
        def collision_stat(path, *args, **kwargs):
            info = real_stat(path, *args, **kwargs)
            if mutation == 'rewrite_masked' and (info.st_dev, info.st_ino) == leaf_id:
                return leaf
            return info

        output = io.StringIO()
        with patch.object(os, 'fstat', frozen_directory_fstat), patch.object(os, 'stat', collision_stat):
            if mode == 'strict':
                with patch.object(sys, 'argv', ['strict.py', str(self.box)]), contextlib.redirect_stdout(output):
                    try:
                        runpy.run_path(str(ROOT / 'lib/query/strict.py'), run_name='__main__',
                                       init_globals={'_test_listing_boundary': hook})
                        code = 0
                    except SystemExit as exc:
                        code = exc.code
                complete = 'completeness=complete' in output.getvalue()
            else:
                with patch.object(scanner, '_test_listing_boundary', hook, create=True), contextlib.redirect_stdout(output):
                    code = query.main(['--root', str(self.box)])
                complete = json.loads(output.getvalue())['complete']
        self.assertEqual(fired, ['beta/inbox'], 'test must mutate exactly at the target boundary')
        self.assertFalse(complete, (mode, mutation, code, output.getvalue()))
        self.assertNotEqual(code, 0, (mode, mutation, output.getvalue()))

    def check_rewrite_after_reread(self, mode):
        # Model a same-tick metadata collision and inject an actual rewrite
        # immediately before the final fstat, after the second header read.
        leaf = self.box / 'beta' / 'inbox' / 'existing.md'
        real_fstat, real_stat = os.fstat, os.stat
        baseline = real_stat(leaf)
        identity = (baseline.st_dev, baseline.st_ino)
        calls = []
        def collision_fstat(fd):
            info = real_fstat(fd)
            if (info.st_dev, info.st_ino) != identity:
                return info
            calls.append(fd)
            if len(calls) == 4:
                writer = os.open(leaf, os.O_RDWR)
                try:
                    os.pwrite(writer, LETTER.replace(b'alpha', b'gamma'), 0)
                finally:
                    os.close(writer)
                info = real_fstat(fd)
            return baseline
        def collision_stat(path, *args, **kwargs):
            info = real_stat(path, *args, **kwargs)
            return baseline if (info.st_dev, info.st_ino) == identity else info

        output = io.StringIO()
        with patch.object(os, 'fstat', collision_fstat), patch.object(os, 'stat', collision_stat), contextlib.redirect_stdout(output):
            if mode == 'strict':
                with patch.object(sys, 'argv', ['strict.py', str(self.box)]):
                    try:
                        runpy.run_path(str(ROOT / 'lib/query/strict.py'), run_name='__main__')
                        code = 0
                    except SystemExit as exc:
                        code = exc.code
                complete = 'completeness=complete' in output.getvalue()
            else:
                code = query.main(['--root', str(self.box)])
                complete = json.loads(output.getvalue())['complete']
        self.assertEqual(len(calls), 4, 'mutation must happen at the final file fstat')
        self.assertIn(b'from: gamma', leaf.read_bytes(), 'the second-read window was exercised')
        self.assertFalse(complete, (mode, code, output.getvalue()))
        self.assertNotEqual(code, 0, (mode, output.getvalue()))

    @unittest.expectedFailure
    def test_strict_rewrite_after_reread(self): self.check_rewrite_after_reread('strict')
    @unittest.expectedFailure
    def test_compat_rewrite_after_reread(self): self.check_rewrite_after_reread('compat')

    def test_strict_add(self): self.check_mutation('strict', 'add')
    def test_strict_remove(self): self.check_mutation('strict', 'remove')
    def test_strict_replace(self): self.check_mutation('strict', 'replace')
    @unittest.expectedFailure
    def test_strict_transient(self): self.check_mutation('strict', 'transient')
    def test_strict_rewrite(self): self.check_mutation('strict', 'rewrite')
    def test_strict_rewrite_masked(self): self.check_mutation('strict', 'rewrite_masked')
    def test_compat_add(self): self.check_mutation('compat', 'add')
    def test_compat_remove(self): self.check_mutation('compat', 'remove')
    def test_compat_replace(self): self.check_mutation('compat', 'replace')
    @unittest.expectedFailure
    def test_compat_transient(self): self.check_mutation('compat', 'transient')
    def test_compat_rewrite(self): self.check_mutation('compat', 'rewrite')
    def test_compat_rewrite_masked(self): self.check_mutation('compat', 'rewrite_masked')


if __name__ == '__main__':
    unittest.main(verbosity=2)
