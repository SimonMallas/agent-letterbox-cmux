#!/usr/bin/env python3
"""Shell, both direct Python readers, and fastpath share one SHOWN rule.

Lengths 0..66 of the byte "x", plus the odd marks from the parity review,
must agree on exit code, stdout, and stderr. A bad filter is the known
exception: the shell gates before filter checks, and the Python readers
validate the filter first. That order stays. The Python text is the filter
error only, never the letter.
"""
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LETTERBOX = ROOT / "bin" / "letterbox"
ID = "2026-11-13T120001-alpha-info-live-a0000001"
BODY = "synthetic-body-marker"
ACTION = b"this release reads flat-v1 only, use a release that supports the box format\n"
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


def refusal(shown):
    return b"letterbox: format refusal: box format is " + shown + b"; " + ACTION


def seed():
    parent = "/private/tmp" if os.path.isdir("/private/tmp") else None
    work = tempfile.mkdtemp(prefix="lb-gate-parity-", dir=parent)
    box = Path(work).resolve()
    for seat in ("alpha", "beta"):
        (box / seat / "inbox").mkdir(parents=True)
        (box / seat / "processed").mkdir()
    (box / "alpha" / "inbox" / f"{ID}.md").write_text(LETTER)
    return box


def clear_mark(box):
    mark = box / "format.mark"
    if not mark.is_symlink() and mark.is_dir():
        mark.rmdir()
        return
    if mark.exists() or mark.is_symlink():
        mark.chmod(0o644)
        mark.unlink()


def run(argv, env=None):
    return subprocess.run(argv, capture_output=True, env=env, timeout=10)


def direct(name, box, *filters):
    script = str(ROOT / "lib" / "query" / name)
    if name == "strict.py":
        argv = [sys.executable, "-I", "-B", script, str(box), *filters]
    else:
        argv = [sys.executable, "-I", "-B", script, "--root", str(box), *filters]
    return run(argv)


def shell(box, *args):
    env = os.environ.copy()
    env.update({
        "LETTERBOX_DIR": str(box),
        "LETTERBOX_AGENT": "alpha",
        "LETTERBOX_DOORBELL": "/nonexistent-test-adapter",
        "LETTERBOX_NOTES_DIR": "",
    })
    return run([str(LETTERBOX), *args], env=env)


def fast(kind, box):
    script = str(ROOT / "lib" / "fast" / "fastpath.py")
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


class FormatGateParity(unittest.TestCase):
    def assert_same(self, procs):
        first = procs[0]
        for proc in procs[1:]:
            self.assertEqual(proc.returncode, first.returncode)
            self.assertEqual(proc.stdout, first.stdout)
            self.assertEqual(proc.stderr, first.stderr)

    def assert_refused(self, proc, shown):
        self.assertEqual(proc.returncode, 1)
        self.assertEqual(proc.stdout, b"")
        self.assertEqual(proc.stderr, refusal(shown))
        self.assertNotIn(BODY.encode(), proc.stdout)
        self.assertNotIn(ID.encode(), proc.stdout + proc.stderr)

    def assert_trio(self, box, shown):
        procs = (
            shell(box, "query", "type=info"),
            direct("strict.py", box, "type=info"),
            direct("query.py", box, "type=info"),
            fast("check", box),
            fast("resolve", box),
        )
        self.assert_same(procs)
        for proc in procs:
            self.assert_refused(proc, shown)

    def test_every_length_of_x_matches(self):
        box = seed()
        try:
            mark = box / "format.mark"
            for size in range(0, 67):
                mark.write_bytes(b"x" * size)
                shown = b"unreadable" if size == 0 or size > 64 else b"'" + b"x" * size + b"'"
                with self.subTest(size=size):
                    self.assert_trio(box, shown)
        finally:
            subprocess.run(["rm", "-rf", str(box)], check=False)

    def test_odd_marks_match(self):
        box = seed()
        try:
            cases = {
                "cr": b"\r",
                "nul": b"\x00",
                "two-newlines": b"\n\n",
                "quote": b"'",
                "backslash": b"\\",
            }
            mark = box / "format.mark"
            for name, data in cases.items():
                mark.write_bytes(data)
                with self.subTest(mark=name):
                    self.assert_trio(box, b"unreadable")
            clear_mark(box)
            mark.mkdir()
            with self.subTest(mark="directory"):
                self.assert_trio(box, b"unreadable")
            clear_mark(box)
            os.mkfifo(mark)
            with self.subTest(mark="fifo"):
                self.assert_trio(box, b"unreadable")
            clear_mark(box)
            # Mode 000 is unreadable for a normal user. Root ignores the mode
            # bits and can still read the mark. Expect whichever this process
            # can actually do. Shell and Python still have to agree.
            mark.write_bytes(b"month-v2\n")
            mark.chmod(0)
            try:
                readable = mark.read_bytes() == b"month-v2\n"
            except OSError:
                readable = False
            shown = b"'month-v2'" if readable else b"unreadable"
            with self.subTest(mark="unreadable-permissions", readable=readable):
                self.assert_trio(box, shown)
        finally:
            mark = box / "format.mark"
            if mark.exists() and not mark.is_dir():
                mark.chmod(0o644)
            subprocess.run(["rm", "-rf", str(box)], check=False)

    def test_bad_filter_is_checked_before_the_python_gate(self):
        """Known difference. Left in place: Python stdout is the filter error only."""
        box = seed()
        try:
            (box / "format.mark").write_text("month-v2\n")
            shell_bad = shell(box, "query", "bogus=1")
            strict_bad = direct("strict.py", box, "bogus=1")
            query_bad = direct("query.py", box, "bogus=1")
            self.assert_refused(shell_bad, b"'month-v2'")
            self.assertEqual(strict_bad.returncode, 2)
            self.assertEqual(strict_bad.stderr, b"")
            self.assertIn(b"invalid_filter", strict_bad.stdout)
            self.assertNotIn(ID.encode(), strict_bad.stdout)
            self.assertNotIn(BODY.encode(), strict_bad.stdout)
            self.assertEqual(query_bad.returncode, 2)
            self.assertEqual(query_bad.stderr, b"")
            self.assertEqual(
                query_bad.stdout,
                b'{"complete":false,"error":"invalid_filter","schema":"letterbox.query.compat.v2"}\n',
            )
            self.assertNotIn(ID.encode(), query_bad.stdout)
            self.assertNotEqual(shell_bad.stdout, strict_bad.stdout)
            clear_mark(box)
            shell_ok = shell(box, "query", "bogus=1")
            strict_ok = direct("strict.py", box, "bogus=1")
            self.assertEqual(shell_ok.returncode, strict_ok.returncode)
            self.assertEqual(shell_ok.stdout, strict_ok.stdout)
            self.assertEqual(shell_ok.stderr, strict_ok.stderr)
            self.assertIn(b"invalid_filter", shell_ok.stdout)
            self.assertNotIn(b"format refusal", shell_ok.stderr)
        finally:
            subprocess.run(["rm", "-rf", str(box)], check=False)


if __name__ == "__main__":
    unittest.main()
