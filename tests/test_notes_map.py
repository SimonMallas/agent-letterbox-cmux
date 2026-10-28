"""Map age at sweep: LETTERBOX_NOTES_DIR notes carry as-of and threads; check says how far the record moved."""
import re
import sys
import unittest

from test_query import MailboxCase


class NotesMapTests(MailboxCase):
    def setUp(self):
        super().setUp()
        self.notes = self.work / "notes"
        self.notes.mkdir()
        self.env["LETTERBOX_NOTES_DIR"] = str(self.notes)

    def note(self, name, *lines):
        (self.notes / name).write_text("\n".join(lines) + "\n\nbody\n", encoding="utf-8")

    def check(self, *args, agent="alpha"):
        result = self.command("check", *args, env=dict(self.env, LETTERBOX_AGENT=agent))
        self.assertEqual(result.returncode, 0, (result.stdout, result.stderr))
        self.assertNotIn("BODY-MUST-NOT-APPEAR", result.stdout)
        return [line for line in result.stdout.splitlines() if line.startswith("map")]

    def test_unset_is_silent(self):
        del self.env["LETTERBOX_NOTES_DIR"]
        self.assertEqual(self.check(), [])
        self.assertEqual(self.check("--maps"), [])

    def test_configured_absence_is_never_silent(self):
        self.env["LETTERBOX_NOTES_DIR"] = str(self.work / "missing")
        self.assertEqual(self.check(), ["map: notes path %s unreadable" % (self.work / "missing")])
        self.assertEqual(self.check("--maps"), ["map: notes path %s unreadable" % (self.work / "missing")])

    def test_plain_check_prints_one_hint_line(self):
        self.note("design.md", "as-of: 2026-01-01T00:00:00Z", "threads: t1")
        self.note("loose.md", "# no cursor here")
        (self.notes / ".lint-baseline").write_text("x\n")
        self.assertEqual(self.check(), [
            "map: 2 notes, 1 uncursored · letterbox check --maps for letters since each cursor"])

    def test_only_for_the_agents_own_check(self):
        self.note("design.md", "as-of: 2026-01-01T00:00:00Z", "threads: t1")
        self.assertEqual(self.check("beta"), [])

    def test_maps_count_letters_since_the_cursor(self):
        self.note("design.md", "rule: kit header", "as-of: 2026-01-10T00:00:00Z", "threads: t1, t2")
        self.letter("t1", sent="2026-01-01T00:00:00Z")
        self.letter("t1-before", thread="t1", sent="2026-01-09T23:59:59Z")
        self.letter("t1-at", thread="t1", sent="2026-01-10T00:00:00Z")
        self.letter("t1-after", agent="alpha", thread="t1", sent="2026-01-11T00:00:00Z")
        self.letter("t1-reply", folder="processed", re="t1", sent="2026-01-12T00:00:00+00:00")
        self.letter("t2-after", thread="t2", sent="2026-01-13T00:00:00Z")
        self.letter("t2-no-time", thread="t2", sent="")
        self.letter("t3-after", thread="t3", sent="2026-01-13T00:00:00Z")
        [line] = self.check("--maps")
        self.assertRegex(line, r"^map design\.md: as-of 2026-01-10T00:00:00Z \(\d+d\) · "
                               r"3 letters since in 2 threads · 1 unknown-time$")

    def test_cursor_classes(self):
        self.note("a-uncursored.md", "threads: t1")
        self.note("b-local.md", "as-of: 2026-01-10T00:00:00+01:00", "threads: t1")
        self.note("c-letter-id.md", "as-of: 2026-01-10T000000-alpha-request-x-abcd1234", "threads: t1")
        self.note("d-no-threads.md", "as-of: 2026-01-10T00:00:00Z")
        lines = self.check("--maps")
        self.assertEqual(lines[:3], ["map a-uncursored.md: uncursored",
                                     "map b-local.md: as-of not ISO-8601 UTC",
                                     "map c-letter-id.md: as-of not ISO-8601 UTC"])
        self.assertRegex(lines[3], r"^map d-no-threads\.md: as-of 2026-01-10T00:00:00Z \(\d+d\) · no threads listed$")

    def test_count_is_capped_per_thread(self):
        self.note("busy.md", "as-of: 2026-01-01T00:00:00Z", "threads: t1")
        for n in range(201):
            self.letter("t1-%03d" % n, thread="t1", sent="2026-01-02T00:00:00Z")
        [line] = self.check("--maps")
        self.assertTrue(line.endswith("· 200+ letters since in 1 thread · capped at 200 per thread"), line)

    def test_maps_are_read_only(self):
        self.note("design.md", "as-of: 2026-01-01T00:00:00Z", "threads: t1")
        self.letter("t1", sent="2026-01-02T00:00:00Z")
        before = self.snapshot()
        self.check("--maps")
        self.check()
        self.assertEqual(self.snapshot(), before)


if __name__ == "__main__":
    sys.dont_write_bytecode = True
    unittest.main(verbosity=1)
