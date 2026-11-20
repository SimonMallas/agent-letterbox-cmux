#!/usr/bin/env python3
"""Direct Python readers honour format gate G. Synthetic boxes only."""
import contextlib
import io
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
# Frozen pre-gate tree. HEAD of a later checkout is not this baseline, and a
# copy with no git uses the same files. A missing or identical baseline fails.
BASELINE = ROOT / "tests" / "fixtures" / "pre-gate"
sys.path.insert(0, str(ROOT / "lib" / "query"))
import format_gate  # noqa: E402

ID = "2026-11-13T120001-alpha-info-live-a0000001"
BODY = "synthetic-body-marker"
LETTER = f"""---
id: {ID}
from: alpha
to: beta
type: info
re:
thread: {ID}
priority: next
requires_ack: false
deadline:
---
{BODY}
"""
ACTION = b"this release reads flat-v1 only, use a release that supports the box format\n"


def refusal(shown):
    return b"letterbox: format refusal: box format is " + shown + b"; " + ACTION


def seed(mark):
    parent = "/private/tmp" if os.path.isdir("/private/tmp") else None
    work = tempfile.mkdtemp(prefix="lb-gate-py-", dir=parent)
    box = Path(work).resolve()
    for seat in ("alpha", "beta"):
        (box / seat / "inbox").mkdir(parents=True)
        (box / seat / "processed").mkdir()
    (box / "alpha" / "inbox" / f"{ID}.md").write_text(LETTER)
    if mark == "flat":
        (box / "format.mark").write_text("flat-v1\n")
    elif mark == "bare":
        (box / "format.mark").write_bytes(b"flat-v1")
    elif mark == "month":
        (box / "format.mark").write_text("month-v2\n")
    elif mark == "symlink":
        (box / "format.mark.real").write_text("flat-v1\n")
        (box / "format.mark").symlink_to("format.mark.real")
    elif mark == "oversize":
        (box / "format.mark").write_bytes(b"\0" * 65)
    elif mark == "nonascii":
        (box / "format.mark").write_bytes(b"month-\xff\n")
    elif mark != "absent":
        raise AssertionError(mark)
    return box


def run(argv):
    return subprocess.run(argv, capture_output=True)


def baseline_readers(test):
    """Return the frozen pre-gate tree. Missing or identical to the candidate fails."""
    strict = BASELINE / "lib" / "query" / "strict.py"
    fast = BASELINE / "lib" / "fast" / "fastpath.py"
    if not strict.is_file() or not fast.is_file():
        test.fail("baseline pre-gate fixture is missing")
    if strict.read_bytes() == (ROOT / "lib" / "query" / "strict.py").read_bytes():
        test.fail("baseline strict.py is the candidate")
    if fast.read_bytes() == (ROOT / "lib" / "fast" / "fastpath.py").read_bytes():
        test.fail("baseline fastpath.py is the candidate")
    return BASELINE


def fastpath(tree, kind, box):
    script = str(tree / "lib" / "fast" / "fastpath.py")
    if kind == "check":
        argv = [
            sys.executable, "-I", "-B", script, "check",
            str(box / "alpha" / "inbox"), "alpha", "1700000000", "999999999", "14", "false",
        ]
    else:
        argv = [
            sys.executable, "-I", "-B", script, "resolve",
            str(box), "a0000001", "nudge", "alpha",
        ]
    return run(argv)


def reader(tree, name, box):
    script = str(tree / "lib" / "query" / name)
    if name == "strict.py":
        argv = [sys.executable, "-I", "-B", script, str(box), "type=info"]
    else:
        argv = [sys.executable, "-I", "-B", script, "--root", str(box), "type=info"]
    return run(argv)


class FormatGateReaders(unittest.TestCase):
    def assert_refused(self, proc, shown):
        self.assertEqual(proc.returncode, 1)
        self.assertEqual(proc.stdout, b"")
        self.assertEqual(proc.stderr, refusal(shown))
        self.assertNotIn(BODY.encode(), proc.stdout)
        self.assertNotIn(ID.encode(), proc.stdout)

    def test_direct_readers_refuse_a_named_mark(self):
        box = seed("month")
        try:
            for name in ("strict.py", "query.py"):
                self.assert_refused(reader(ROOT, name, box), b"'month-v2'")
        finally:
            subprocess.run(["rm", "-rf", str(box)])

    def test_direct_readers_refuse_unreadable_marks(self):
        for mark in ("symlink", "oversize", "nonascii"):
            box = seed(mark)
            try:
                for name in ("strict.py", "query.py"):
                    with self.subTest(mark=mark, reader=name):
                        self.assert_refused(reader(ROOT, name, box), b"unreadable")
            finally:
                subprocess.run(["rm", "-rf", str(box)])

    def test_shell_and_python_stderr_match(self):
        box = seed("month")
        try:
            env = os.environ.copy()
            env.update(LETTERBOX_DIR=str(box), LETTERBOX_AGENT="alpha",
                       LETTERBOX_DOORBELL="/nonexistent-test-adapter", LETTERBOX_NOTES_DIR="")
            shell = subprocess.run([str(ROOT / "bin" / "letterbox"), "query", "type=info"],
                                   capture_output=True, env=env)
            direct = reader(ROOT, "strict.py", box)
            self.assertEqual(shell.returncode, 1)
            self.assertEqual(shell.stdout, b"")
            self.assertEqual(shell.stderr, direct.stderr)
        finally:
            subprocess.run(["rm", "-rf", str(box)])

    def test_absent_and_flat_match_the_base_readers(self):
        base = baseline_readers(self)
        text = (base / "lib" / "query" / "strict.py").read_text(encoding="utf-8")
        self.assertNotIn("format_gate", text)
        for mark in ("absent", "flat", "bare"):
            box = seed(mark)
            try:
                for name in ("strict.py", "query.py"):
                    old = reader(base, name, box)
                    new = reader(ROOT, name, box)
                    with self.subTest(mark=mark, reader=name):
                        self.assertEqual(new.returncode, old.returncode)
                        self.assertEqual(new.stdout, old.stdout)
                        self.assertEqual(new.stderr, old.stderr)
                        self.assertIn(ID.encode(), new.stdout)
            finally:
                subprocess.run(["rm", "-rf", str(box)], check=False)

    def test_absent_and_flat_match_the_base_fastpath(self):
        base = baseline_readers(self)
        archived = base / "lib" / "fast" / "fastpath.py"
        self.assertNotIn("format_gate", archived.read_text(encoding="utf-8"))
        current = (ROOT / "lib" / "fast" / "fastpath.py").read_text(encoding="utf-8")
        self.assertIn("format_gate", current)
        for mark in ("absent", "flat", "bare"):
            box = seed(mark)
            try:
                for kind in ("check", "resolve"):
                    old = fastpath(base, kind, box)
                    new = fastpath(ROOT, kind, box)
                    with self.subTest(mark=mark, kind=kind):
                        self.assertEqual(new.returncode, 0)
                        self.assertEqual(new.returncode, old.returncode)
                        self.assertEqual(new.stdout, old.stdout)
                        self.assertEqual(new.stderr, old.stderr)
                        if kind == "check":
                            self.assertIn(b"2026-11-13T120001", new.stdout)
                            self.assertIn(b"a0000001", new.stdout)
                        else:
                            self.assertIn(b"a0000001.md\n", new.stdout)
            finally:
                subprocess.run(["rm", "-rf", str(box)], check=False)

    @unittest.expectedFailure
    def test_swap_after_preflight_is_still_served(self):
        """Barrier-class non-atomicity. G reads the mark once and does not close a swap."""
        box = seed("flat")
        real = format_gate.check

        def swap(root):
            real(root)
            Path(root, "format.mark").write_bytes(b"month-v2\n")

        format_gate.check = swap
        stdout = io.StringIO()
        try:
            import runpy
            with _argv(["strict.py", str(box)]), contextlib.redirect_stdout(stdout):
                try:
                    runpy.run_path(str(ROOT / "lib" / "query" / "strict.py"), run_name="__main__")
                except SystemExit as exc:
                    if Path(box, "format.mark").read_bytes() != b"month-v2\n":
                        raise RuntimeError("swap did not run") from exc
                    self.assertEqual(exc.code, 1)
                    self.assertEqual(stdout.getvalue(), "")
                    return
            if Path(box, "format.mark").read_bytes() != b"month-v2\n":
                raise RuntimeError("swap did not run")
            self.assertEqual(stdout.getvalue(), "")
        finally:
            format_gate.check = real
            subprocess.run(["rm", "-rf", str(box)])


class _argv:
    def __init__(self, argv):
        self.argv = argv
        self.old = None

    def __enter__(self):
        self.old = sys.argv
        sys.argv = self.argv

    def __exit__(self, *exc):
        sys.argv = self.old


if __name__ == "__main__":
    unittest.main()
