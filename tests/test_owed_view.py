"""Open loops (view=owed): a preset over compat-v2's answered facts, no second scan."""
import json
import sys
import unittest

from test_query import MailboxCase

NOW = "2026-02-01T00:00:00Z"


class OwedViewTests(MailboxCase):
    def owed(self, *args, code=0, now=NOW):
        result = self.command("query", "view=owed", *args, *(("--now", now) if now else ()))
        self.assertEqual(result.returncode, code, (result.stdout, result.stderr))
        self.assertEqual(result.stderr, "")
        self.assertNotIn("BODY-MUST-NOT-APPEAR", result.stdout)
        return json.loads(result.stdout)

    def ids(self, data):
        return [card["identity"] for card in data["cards"]]

    def reply_file(self, ident, *, agent="beta", re=None):
        outbox = self.box / agent / "outbox"
        outbox.mkdir(exist_ok=True)
        (outbox / ("reply-" + ident + ".md")).write_text(
            "---\nid: reply-%s\nfrom: %s\nto: chat-bridge\nre: %s\n---\nsent text\n"
            % (ident, agent, re or ident), encoding="utf-8")

    def test_owed_is_every_unfiled_obligating_letter_in_the_agents_inbox(self):
        self.letter("open-request")
        self.letter("filed-request", folder="processed")
        self.letter("plain-info", type="info", requires_ack="false")
        self.letter("info-wanting-ack", type="info", requires_ack="true")
        self.letter("someone-elses", agent="alpha", **{"from": "beta", "to": "alpha"})
        answered = self.letter("answered-request")
        self.letter("result-a", agent="alpha", **{"from": "beta", "to": "alpha",
                    "type": "result", "re": "answered-request"})
        data = self.owed("to=beta")
        self.assertEqual(data["view"], "owed")
        self.assertTrue(data["complete"])
        self.assertEqual(sorted(self.ids(data)), ["answered-request", "info-wanting-ack", "open-request"])
        self.assertEqual(data["counts"]["owed"], 3)
        # Answering annotates; only filing takes a letter off the view.
        tiers = {c["identity"]: c["tier"] for c in data["cards"]}
        self.assertEqual(tiers["answered-request"], "ANSWERED")
        self.assertEqual(data["counts"]["answered"], 1)
        answered.rename(self.box / "beta/processed" / answered.name)
        self.assertEqual(sorted(self.ids(self.owed("to=beta"))), ["info-wanting-ack", "open-request"])

    def test_only_the_addressees_terminal_answers(self):
        self.letter()
        self.letter("third-party", agent="alpha", **{"from": "gamma", "to": "alpha",
                    "type": "result", "re": "request-a"})
        self.letter("thanks", agent="alpha", **{"from": "beta", "to": "alpha",
                    "type": "info", "re": "request-a"})
        tier = lambda: [(c["identity"], c["tier"]) for c in self.owed("to=beta")["cards"]]
        self.assertEqual(tier(), [("request-a", "UNACKED")])
        self.letter("nack-a", agent="alpha", **{"from": "beta", "to": "alpha",
                    "type": "nack", "re": "request-a"})
        self.assertEqual(tier(), [("request-a", "ANSWERED")])

    def test_tiers_come_from_ack_letters_not_sidecars(self):
        self.letter("acked")
        self.letter("ack-1", agent="alpha", **{"from": "beta", "to": "alpha",
                    "type": "ack", "re": "acked"})
        self.letter("sidecar-only")
        (self.box / "beta/inbox/sidecar-only.md.ack").write_text("acked_at: now\n")
        tiers = {c["identity"]: c["tier"] for c in self.owed("to=beta")["cards"]}
        self.assertEqual(tiers, {"acked": "ACCEPTED-OPEN", "sidecar-only": "UNACKED"})

    def test_relay_letters_read_only_the_reply_file(self):
        # A sender with no mailbox here is a relay: its reply never lands in a
        # Letterbox inbox, so the bridge's one reply file is the evidence.
        self.letter("phone-a", type="info", requires_ack="false", **{"from": "chat-bridge"})
        self.letter("phone-b", type="info", requires_ack="false", **{"from": "chat-bridge"})
        self.letter("phone-c", type="info", requires_ack="false", **{"from": "external-bridge"})
        self.reply_file("phone-b")
        (self.box / "beta/outbox/draft-phone-a.md").write_text(
            "---\nid: draft\nfrom: beta\nto: chat-bridge\nre: phone-a\n---\n", encoding="utf-8")
        self.reply_file("phone-c", re="something-else")
        cards = {c["identity"]: c for c in self.owed("to=beta")["cards"]}
        self.assertEqual(set(cards), {"phone-a", "phone-b", "phone-c"})
        self.assertEqual((cards["phone-a"]["relay_reply"], cards["phone-a"]["tier"]), ("none", "UNACKED"))
        self.assertEqual((cards["phone-b"]["relay_reply"], cards["phone-b"]["tier"]),
                         ("composed", "ANSWERED-UNPROVEN"))
        self.assertEqual(cards["phone-b"]["note"], "answered (delivery unproven)")
        self.assertEqual(cards["phone-c"]["relay_reply"], "unreadable")
        self.assertTrue(all(c["relay"] for c in cards.values()))

    def test_unknown_time_is_counted_and_listed_last(self):
        self.letter("late", sent="2026-01-03T00:00:00Z")
        self.letter("no-time", sent="")
        self.letter("early", sent="2026-01-02T00:00:00Z")
        data = self.owed("to=beta")
        self.assertEqual(self.ids(data), ["early", "late", "no-time"])
        self.assertEqual(data["counts"]["unknown_time"], 1)

    def test_overdue_is_strictly_before_now(self):
        self.letter("past", deadline="2026-01-31T23:59:59Z")
        self.letter("exact", deadline=NOW)
        self.letter("future", deadline="2026-03-01T00:00:00Z")
        self.letter("garbled", deadline="tomorrow")
        self.letter("none")
        overdue = {c["identity"]: c["overdue"] for c in self.owed("to=beta")["cards"]}
        self.assertEqual(overdue, {"past": "yes", "exact": "no", "future": "no",
                                   "garbled": "unknown", "none": "no"})
        counts = self.owed("to=beta")["counts"]
        self.assertEqual((counts["overdue"], counts["overdue_unknown"]), (1, 1))

    def test_limit_cuts_oldest_first_and_marks_truncation(self):
        for day in range(1, 23):
            self.letter("r%02d" % day, sent="2026-01-%02dT00:00:00Z" % day)
        data = self.owed("to=beta")
        self.assertEqual((len(data["cards"]), data["limit"], data["truncated"]), (20, 20, True))
        self.assertEqual(data["counts"]["owed"], 22)
        self.assertEqual(self.ids(data)[0], "r01")
        data = self.owed("to=beta", "--limit", "2")
        self.assertEqual((self.ids(data), data["truncated"]), (["r01", "r02"], True))
        data = self.owed("to=beta", "--limit", "0")
        self.assertEqual((len(data["cards"]), data["truncated"]), (22, False))

    def test_incomplete_scan_claims_nothing(self):
        self.letter()
        (self.box / "beta/inbox/bad.md").write_text("no header\n", encoding="utf-8")
        data = self.owed("to=beta", code=2)
        self.assertFalse(data["complete"])
        self.assertEqual([c["owed"] for c in data["cards"]], ["unknown"])
        self.assertEqual((data["counts"]["owed"], data["counts"]["owed_unknown"]), (0, 1))

    def test_refusals(self):
        for args in (("view=owed",), ("view=open", "to=beta"), ("view=owed", "to=beta", "from=alpha"),
                     ("view=owed", "to=beta", "--limit", "-1"), ("view=owed", "to=beta", "--now", "soon"),
                     ("--compat-v2", "to=beta", "--limit", "5"),
                     ("--compat-v2", "view=owed", "to=beta", "--participant", "beta")):
            result = self.command("query", *args)
            self.assertEqual(result.returncode, 2, args)
            self.assertFalse(json.loads(result.stdout)["complete"], args)

    def test_read_only_and_scope_stated(self):
        self.letter()
        before = self.snapshot()
        data = self.owed("to=beta")
        self.assertEqual(self.snapshot(), before)
        self.assertFalse(data["scope"]["whole_tree_absence_claim"])
        self.assertEqual(data["scope"]["folder_patterns"], ["inbox", "processed"])
        self.assertEqual(data["scope"]["relay_reply_file"], "<agent>/outbox/reply-<id>.md")
        self.assertEqual(self.owed("to=alpha")["cards"], [])


if __name__ == "__main__":
    sys.dont_write_bytecode = True
    unittest.main(verbosity=1)
