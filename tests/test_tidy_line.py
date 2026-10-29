"""Tidy reminder: once it counts enough letters to review for filing, the agent's own check says so in one line."""
import os
import sys
import unittest

from test_query import MailboxCase

LINE = "%d non-task letters to review for filing — letterbox file to tidy."


class TidyLineTests(MailboxCase):
    def check(self, *args, agent="beta", **env):
        result = self.command("check", *args, env=dict(self.env, LETTERBOX_AGENT=agent, **env))
        self.assertEqual(result.returncode, 0, (result.stdout, result.stderr))
        self.assertNotIn("BODY-MUST-NOT-APPEAR", result.stdout)
        return [line for line in result.stdout.splitlines() if line.endswith("letterbox file to tidy.")]

    def info(self, count, **fields):
        for n in range(count):
            self.letter("info-%d" % n, type="info", requires_ack="false", **fields)

    def phone(self, ident, sender="chat-bridge", type="info"):
        self.letter(ident, type=type, requires_ack="false", **{"from": sender})

    def reply_file(self, ident, *, re=None, name=None):
        outbox = self.box / "beta" / "outbox"
        outbox.mkdir(exist_ok=True)
        path = outbox / (name or "reply-" + ident + ".md")
        path.write_text("---\nid: reply-%s\nfrom: beta\nto: chat-bridge\nre: %s\n---\nsent text\n"
                        % (ident, re or ident), encoding="utf-8")
        return path

    def test_one_line_from_the_fifth_letter(self):
        self.info(4)
        self.assertEqual(self.check(), [])
        self.letter("info-4", type="info", requires_ack="false")
        self.assertEqual(self.check(), [LINE % 5])
        self.assertEqual(self.check("--recent"), [LINE % 5])

    def test_counts_non_requests_and_replied_phone_letters_only(self):
        self.info(3)
        self.letter("inbound-result", type="result", requires_ack="false", re="mine")
        self.letter("task")
        self.letter("accepted-task")
        (self.box / "beta/inbox/accepted-task.md.ack").write_text("acked_at: 2026-01-01T12:00:00Z\n")
        self.letter("info-wanting-ack", type="info", requires_ack="true")
        self.letter("request-no-ack", requires_ack="false")
        self.letter("filed-info", folder="processed", type="info", requires_ack="false")
        (self.box / "beta/inbox/unclosed.md").write_text(
            "---\nid: unclosed\nfrom: alpha\ntype: info\nrequires_ack: false\n\nbody\n")
        self.phone("phone-open")
        self.phone("phone-replied")
        self.reply_file("phone-replied")
        # A phone letter counts whatever its type: nobody can mark a phone message a request.
        self.phone("phone-request", type="request")
        self.reply_file("phone-request")
        # Reserved names are phone letters even where they exist in the box.
        (self.box / "external-bridge").mkdir()
        (self.box / "locks").mkdir()
        self.phone("phone-external", sender="external-bridge")
        self.phone("phone-locks", sender="locks")
        self.phone("phone-mismatch")
        self.reply_file("phone-mismatch", re="something-else")
        self.phone("phone-draft")
        self.reply_file("phone-draft", name="draft-phone-draft.md")
        self.phone("phone-link")
        os.symlink(self.reply_file("phone-link", name="kept.md"), self.box / "beta/outbox/reply-phone-link.md")
        # 3 info + an inbound result + the two phone letters whose reply is composed.
        self.assertEqual(self.check(LETTERBOX_CHECK_TIDY_AT="1"), [LINE % 6])

    def test_a_symlinked_outbox_is_not_read(self):
        elsewhere = self.work / "elsewhere"
        elsewhere.mkdir()
        (self.box / "beta/outbox").symlink_to(elsewhere)
        self.phone("phone-replied")
        self.reply_file("phone-replied")
        self.assertEqual(self.check(LETTERBOX_CHECK_TIDY_AT="1"), [])

    def test_threshold_is_configurable(self):
        self.info(2)
        self.assertEqual(self.check(LETTERBOX_CHECK_TIDY_AT="2"), [LINE % 2])
        self.assertEqual(self.check(LETTERBOX_CHECK_TIDY_AT="3"), [])
        self.info(6)
        self.assertEqual(self.check(LETTERBOX_CHECK_TIDY_AT="0"), [])
        self.assertEqual(self.check(LETTERBOX_CHECK_TIDY_AT="08"), [])
        self.assertEqual(self.check(LETTERBOX_CHECK_TIDY_AT="five"), [LINE % 6])

    def test_one_letter_is_singular(self):
        self.info(1)
        self.assertEqual(self.check(LETTERBOX_CHECK_TIDY_AT="1"),
                         ["1 non-task letter to review for filing — letterbox file to tidy."])

    def test_only_for_the_agents_own_check(self):
        self.info(5)
        self.info(5, agent="alpha", **{"from": "beta", "to": "alpha"})
        self.assertEqual(self.check("beta", agent="alpha"), [])
        self.assertEqual(self.check(agent="alpha"), [LINE % 5])

    def test_check_stays_read_only(self):
        self.info(5)
        self.phone("phone-replied")
        self.reply_file("phone-replied")
        before = self.snapshot()
        self.check()
        self.assertEqual(self.snapshot(), before)


if __name__ == "__main__":
    sys.dont_write_bytecode = True
    unittest.main(verbosity=1)
