"""Fresh-install writer/query integration, using only disposable mailboxes."""
import datetime as dt
import unittest

from test_query import MailboxCase


class WriterTests(MailboxCase):
    def header(self, path):
        text = path.read_text(encoding="utf-8")
        self.assertTrue(text.startswith("---\n"))
        fields = {}
        for line in text.split("---\n", 2)[1].splitlines():
            key, sep, value = line.partition(":")
            self.assertEqual(sep, ":")
            self.assertNotIn(key, fields)
            fields[key] = value.strip()
        self.assertIn("sent", fields, "every new publication must carry sent")
        return fields

    def send(self, *options, env=None, kind="info", slug="topic"):
        before = set((self.box / "beta/inbox").glob("*.md"))
        result = self.command("send", "beta", kind, slug, *options,
                              input="synthetic message\n", env=env)
        self.assertEqual(result.returncode, 0, (result.stdout, result.stderr))
        added = set((self.box / "beta/inbox").glob("*.md")) - before
        self.assertEqual(len(added), 1)
        path = added.pop()
        return path, self.header(path)

    def assert_utc(self, value):
        self.assertRegex(value, r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$")
        return dt.datetime.strptime(value, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=dt.timezone.utc)

    def clock(self, stamp):
        # The writer's publication clock is deterministic; other date uses
        # delegate to the ordinary tool so reply lifecycle bookkeeping survives.
        date = self.tools / "date"
        log = self.work / "clock-calls"
        date.write_text('#!/bin/bash\n'
                        'if [[ "$*" == "-u +%Y-%m-%dT%H:%M:%SZ" ]]; then\n'
                        '  printf "call\\n" >> "$CLOCK_LOG"\n'
                        '  printf "%s\\n" "$CLOCK_STAMP"\n'
                        'elif [[ "$*" == "-u +%Y-%m-%dT%H%M%S" ]]; then\n'
                        '  printf "second-clock\\n" >> "$CLOCK_LOG"\n'
                        '  printf "2099-12-31T235959\\n"\n'
                        'else\n  exec /bin/date "$@"\nfi\n')
        date.chmod(0o755)
        return dict(self.env, CLOCK_STAMP=stamp, CLOCK_LOG=str(log)), log

    def test_send_has_one_utc_snapshot_for_id_and_sent(self):
        env, log = self.clock("2026-01-01T23:59:59Z")
        path, fields = self.send(env=env)
        self.assert_utc(fields["sent"])
        self.assertEqual(fields["sent"], "2026-01-01T23:59:59Z")
        compact = fields["sent"].replace(":", "").removesuffix("Z")
        self.assertEqual(fields["id"][:17], compact)
        self.assertEqual(path.stem, fields["id"])
        self.assertEqual(log.read_text(), "call\n")

    def test_reply_own_time_parent_identity_and_retry_bytes(self):
        parent_env, _ = self.clock("2026-01-01T10:00:00Z")
        parent_path, parent = self.send("--ack", kind="request", env=parent_env)
        original = parent_path.read_bytes()
        reply_env = dict(parent_env, LETTERBOX_AGENT="beta", CLOCK_STAMP="2026-01-02T11:00:00Z")
        for kind, stamp in (("ack", "2026-01-02T11:00:00Z"), ("result", "2026-01-02T12:00:00Z")):
            reply_env["CLOCK_STAMP"] = stamp
            result = self.command("reply", parent["id"], kind, "response",
                                  input=kind + " body\n", env=reply_env)
            self.assertEqual(result.returncode, 0, (result.stdout, result.stderr))
            reply_path = self.box / "alpha/inbox" / (parent["id"] + "--beta--" + kind + ".md")
            reply = self.header(reply_path)
            self.assertEqual(reply["id"], parent["id"] + "--beta--" + kind)
            self.assertEqual(reply["id"][:17], parent["id"][:17])
            self.assertGreaterEqual(self.assert_utc(reply["sent"]), self.assert_utc(parent["sent"]))
            self.assertEqual(reply["sent"], stamp)
            self.assertEqual(reply["re"], parent["id"])
            self.assertNotIn("supersedes", reply)
            frozen = reply_path.read_bytes()
            result = self.command("reply", parent["id"], kind, "response",
                                  input=kind + " body\n",
                                  env=dict(reply_env, CLOCK_STAMP="2026-01-03T12:00:00Z"))
            self.assertEqual(result.returncode, 0, (result.stdout, result.stderr))
            self.assertEqual(reply_path.read_bytes(), frozen)
        self.assertEqual((self.box / "beta/processed" / parent_path.name).read_bytes(), original)
        data = self.query("type=result", "since=2026-01-02T00:00:00Z", compat=True)
        self.assertEqual(data["observed_counts"]["selected"], 1)
        self.assertEqual(data["cards"][0]["time_basis"], "sent_utc")

    def test_nack_has_own_sent(self):
        _, parent = self.send("--ack", kind="request")
        result = self.command("reply", parent["id"], "nack", "declined", input="declined\n",
                              env=dict(self.env, LETTERBOX_AGENT="beta"))
        self.assertEqual(result.returncode, 0, result.stderr)
        reply = self.header(self.box / "alpha/inbox" / (parent["id"] + "--beta--nack.md"))
        self.assertGreaterEqual(self.assert_utc(reply["sent"]), self.assert_utc(parent["sent"]))

    def test_new_letters_have_known_compat_time_and_unsuperseded_head(self):
        first_path, first = self.send()
        first_bytes = first_path.read_bytes()
        _, second = self.send("--supersedes", first["id"], slug="revision")
        self.assertEqual(second["supersedes"], first["id"])
        self.assertEqual(first_path.read_bytes(), first_bytes)
        data = self.query("superseded=head", "since=1970-01-01T00:00:00Z", compat=True)
        self.assertEqual(data["observed_counts"]["selected"], 1)
        self.assertEqual(data["cards"][0]["identity"], second["id"])
        self.assertEqual(data["cards"][0]["time_basis"], "sent_utc")
        self.assertEqual(data["cards"][0]["head"], "yes")
        self.assertEqual(data["observed_counts"]["unknown_time"], 0)
        out = self.query("superseded=head", "since=1970-01-01T00:00:00Z")
        self.assertIn("count=1 scanned=2", out)
        self.assertIn('id: "' + second["id"] + '"', out)
        self.assertNotIn('id: "' + first["id"] + '"', out)
        data = self.query("superseded=yes", compat=True)
        self.assertEqual(data["cards"][0]["identity"], first["id"])

    def test_malformed_references_refuse_before_any_write(self):
        invalid = ("", "bad id", "x/y", "a\nb", "a\rb", "a\tb", "$(command)",
                   "x" * 129, "é", "Ａ", "x\x1b[31m")
        for flag in ("--supersedes", "--thread"):
            for value in invalid:
                with self.subTest(flag=flag, value=repr(value)):
                    before = self.snapshot()
                    result = self.command("send", "beta", "info", "invalid", flag, value,
                                          input="body\n")
                    self.assertNotEqual(result.returncode, 0)
                    self.assertEqual(self.snapshot(), before)
                    self.assertEqual(result.stdout, "")

    def test_supersedes_missing_and_repeated_refuse(self):
        for options in (("--supersedes",), ("--supersedes", "one", "--supersedes", "two")):
            before = self.snapshot()
            result = self.command("send", "beta", "info", "invalid", *options, input="body\n")
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(self.snapshot(), before)

    def test_reference_charset_and_maximum_length_preserved(self):
        for value in ("a", "Aa09._:-", "x" * 128):
            _, fields = self.send("--supersedes", value, "--thread", value)
            self.assertEqual(fields["supersedes"], value)
            self.assertEqual(fields["thread"], value)

    def test_unknown_reference_is_diagnostic_not_writer_lookup(self):
        _, fields = self.send("--supersedes", "absent-id")
        self.assertEqual(fields["supersedes"], "absent-id")
        self.assertIn("dangling_supersedes=1", self.query())
        self.assertEqual(self.query(compat=True)["dangling_supersedes"], ["absent-id"])

    def test_foreign_reference_is_annotation_not_mutation(self):
        foreign = self.letter("foreign-id", **{"from": "beta", "to": "alpha"})
        before = foreign.read_bytes()
        _, fields = self.send("--supersedes", "foreign-id")
        self.assertEqual(fields["supersedes"], "foreign-id")
        self.assertEqual(foreign.read_bytes(), before)
        data = self.query("superseded=yes", compat=True)
        self.assertEqual(data["cards"][0]["fields"]["from"], "beta")

    def test_session_and_optional_fields(self):
        _, fields = self.send(env=dict(self.env, LETTERBOX_SESSION="session-a"))
        self.assertEqual(fields["session"], "session-a")
        self.assertNotIn("supersedes", fields)

    def test_legacy_letter_not_rewritten_and_time_stays_unknown(self):
        path = self.letter(sent="")
        before = path.read_bytes()
        self.send()
        data = self.query(compat=True)
        card = next(c for c in data["cards"] if c["identity"] == "request-a")
        self.assertIsNone(card["publication_utc"])
        self.assertEqual(path.read_bytes(), before)


if __name__ == "__main__":
    unittest.main()
