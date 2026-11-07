"""F3 fixtures: only synthetic notes/mailboxes; no live files or transport."""
import contextlib
import hashlib
import io
import json
import unittest
from unittest.mock import patch
from test_query import MailboxCase
import lint_notes
import scope


class LintTests(MailboxCase):
    def setUp(self):
        super().setUp()
        self.notes = self.work / "notes"
        self.notes.mkdir()
        self.env["LETTERBOX_NOTES_DIR"] = str(self.notes)

    def note(self, text, name="map.md"):
        path = self.notes / name
        path.write_text(text, encoding="utf-8")
        return path

    def lint(self, *args, code=0):
        before = self.snapshot()
        out = self.command("lint-notes", "--json", *args)
        self.assertEqual(out.returncode, code, (out.stdout, out.stderr))
        self.assertEqual(self.snapshot(), before)
        return json.loads(out.stdout)

    def test_full_id_resolves(self):
        ident = "2026-10-28T010203-a-0123abcd"
        self.letter(ident)
        self.note(f"as-of: anything\nClaim {ident}.\n")
        self.assertEqual(self.lint()["findings"], [])

    def test_a_symlinked_box_is_read_through(self):
        ident = "2026-10-28T010203-a-0123abcd"
        self.letter(ident)
        self.note(f"as-of: now\nClaim {ident}\n")
        link = self.work / "linked-store"
        link.symlink_to(self.box, target_is_directory=True)
        self.env["LETTERBOX_DIR"] = str(link)
        self.assertEqual(self.lint()["findings"], [])

    def test_orphan(self):
        self.note("as-of: now\nClaim 2026-10-28T010203-missing-abcd1234\n")
        self.assertEqual(self.lint(code=1)["findings"][0]["kind"], "orphan")

    def test_display_tail_and_hash(self):
        ids = ["2026-10-28T010203-a-0123abcd", "2026-10-28T020304-a-u123456789abc"]
        for ident in ids:
            self.letter(ident)
        digest = hashlib.sha256(ids[1].encode()).hexdigest()[:8]
        self.note("as-of: now\nClaim 2026-10-28T010203 · 0123abcd\nClaim 2026-10-28T020304 · " + digest)
        self.assertEqual(self.lint()["findings"], [])

    def test_ambiguous_display(self):
        self.letter("2026-10-28T010203-one-0123abcd")
        self.letter("2026-10-28T010203-two-0123abcd")
        self.note("as-of: now\nClaim 2026-10-28T010203 · 0123abcd\n")
        self.assertEqual([f["kind"] for f in self.lint(code=1)["findings"]], ["ambiguous"])

    def test_stale_uses_query_graph(self):
        old = "2026-10-28T010203-old-0123abcd"
        self.letter(old)
        self.letter("2026-10-28T010204-new-0123abce", supersedes=old)
        self.note(f"as-of: now\nClaim {old}\n")
        self.assertEqual(self.lint(code=1)["findings"][0]["kind"], "stale")

    def test_dangling(self):
        ident = "2026-10-28T010203-new-0123abcd"
        self.letter(ident, supersedes="missing-ancestor")
        self.note(f"as-of: now\nClaim {ident}\n")
        self.assertEqual(self.lint(code=1)["findings"][0]["kind"], "dangling")

    def test_uncursored_null_and_header_window(self):
        self.note("\n" * 20 + "as-of: now\n")
        finding = self.lint(code=1)["findings"][0]
        self.assertEqual(finding["kind"], "uncursored")
        self.assertIsNone(finding["citation"])

    def test_indented_cursor_is_not_uncursored(self):
        for whitespace in ("  ", "\t", " \t "):
            self.note(whitespace + "as-of: 2026-10-28T00:00:00Z  \nClaim\n")
            self.assertEqual(self.lint()["findings"], [])

    def test_invalid_cursor_is_not_uncursored(self):
        self.note("as-of: invalid\nordinary prose\n")
        self.assertEqual(self.lint()["findings"], [])

    def test_formatting_not_orphan(self):
        ident = "2026-10-28T010203-new-0123abcd"
        self.letter(ident)
        self.note(f"as-of: now\nA claim on its own line\n{ident}\n")
        self.assertEqual([f["kind"] for f in self.lint(code=1)["findings"]], ["formatting"])

    def test_baseline_survives_line_renumber(self):
        p = self.note("as-of: now\nClaim 2026-10-28T010203-absent-0123abcd\n")
        first = self.lint("--baseline", code=1)
        self.assertFalse(first["baseline"])
        p.write_text("\n\n" + p.read_text())
        self.assertEqual(self.lint()["findings"], [])
        with p.open("a") as out:
            out.write("Claim 2026-10-28T010204-new-0123abcd\n")
        self.assertEqual(len(self.lint(code=1)["findings"]), 1)

    def test_dotfiles_skipped(self):
        self.note("broken note", ".hidden.md")
        self.lint()

    def test_bad_utf8_refuses(self):
        self.note("").write_bytes(b"\xff")
        self.assertFalse(self.lint(code=2)["complete"])

    def test_symlink_note_refuses(self):
        (self.notes / "linked.md").symlink_to(self.note("as-of: now", "target.txt"))
        self.lint(code=2)

    def test_bad_baseline_refuses(self):
        (self.notes / ".lint-baseline").write_text("not json")
        self.lint(code=2)

    def test_baseline_wrong_shapes_refuse(self):
        for value in ([], {"schema": "letterbox.lint.v1", "keys": [["a", [], "orphan"]]}):
            (self.notes / ".lint-baseline").write_text(json.dumps(value))
            self.lint(code=2)

    def test_legacy_id(self):
        # A known non-timestamp id is a citation, quoted or not.
        self.letter("request-a")
        self.letter("2026-10-28T010203-new-0123abcd", supersedes="request-a")
        self.note("as-of: now\nClaim `request-a`\nClaim request-a\n")
        self.assertEqual([(f["citation"], f["kind"]) for f in self.lint(code=1)["findings"]],
                         [("request-a", "stale"), ("request-a", "stale")])

    def test_code_quoted_words_are_not_citations(self):
        # Flags, commands and field names are written in code quotes; only
        # timestamp ids and ids of letters in scope are citations.
        self.note("as-of: now\nRun `lint-notes` with `--config` and `--text`; read `as-of:` "
                  "and `missing-letter`.\nClaim `2026-10-28T010203-missing-abcd1234`\n")
        self.assertEqual([(f["citation"], f["kind"]) for f in self.lint(code=1)["findings"]],
                         [("2026-10-28T010203-missing-abcd1234", "orphan")])

    def test_same_token_different_timestamp_is_not_ambiguous(self):
        self.letter("2026-10-28T010203-one-0123abcd")
        self.letter("2026-10-28T010204-two-0123abcd")
        self.note("as-of: now\nClaim 2026-10-28T010203 · 0123abcd\n")
        self.lint()

    def test_incomplete_scan_is_not_orphan(self):
        p = self.letter()
        p.write_text("not frontmatter")
        self.note("as-of: now\nClaim 2026-10-28T010203-absent-0123abcd\n")
        data = self.lint(code=2)
        self.assertFalse(data["complete"])
        self.assertEqual(data["reason"], "incomplete_query_scope")

    def test_a_refusal_names_its_reason(self):
        env = dict(self.env)
        del env["LETTERBOX_NOTES_DIR"]
        for args, env, reason in (((), env, "LETTERBOX_NOTES_DIR_unset"),
                                  (("--notes-dir", str(self.work / "missing")), None,
                                   "notes_directory_unreadable")):
            out = self.command("lint-notes", "--json", *args, env=env)
            self.assertEqual(out.returncode, 2, (out.stdout, out.stderr))
            data = json.loads(out.stdout)
            self.assertEqual((data["error"], data["reason"]),
                             ("lint_input_unreadable_or_invalid", reason))

    def lint_while_seats_appear(self, appearances):
        """Run lint in process; a new seat appears after each of the first scans."""
        scans = []
        real = scope.scan

        def moving(*args, **kwargs):
            result = real(*args, **kwargs)
            scans.append(result)
            if len(scans) <= appearances:
                for folder in ("inbox", "processed"):
                    (self.box / ("gamma%d" % len(scans)) / folder).mkdir(parents=True)
            return result
        out = io.StringIO()
        with patch.object(scope, "scan", moving), contextlib.redirect_stdout(out):
            code = lint_notes.main(["--root", str(self.box), "--agent", "alpha",
                                    "--notes-dir", str(self.notes), "--json"])
        return code, json.loads(out.getvalue()), len(scans)

    def test_mail_moving_during_the_scan_is_retried_once(self):
        ident = "2026-10-28T010203-a-0123abcd"
        self.letter(ident)
        self.note(f"as-of: now\nClaim {ident}\n")
        code, data, scans = self.lint_while_seats_appear(1)
        self.assertEqual((code, data["findings"], scans), (0, [], 2))

    def test_mail_that_keeps_moving_fails_with_its_reason(self):
        self.note("as-of: now\nClaim 2026-10-28T010203-absent-0123abcd\n")
        code, data, scans = self.lint_while_seats_appear(5)
        self.assertEqual((code, data["reason"], scans), (2, "mail_changed_during_scan", 2))


if __name__ == "__main__":
    unittest.main()
