"""Fresh-install writer/query integration, using only disposable mailboxes."""
import datetime as dt
import shlex
import shutil
import unittest

from test_query import MailboxCase, ROOT


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
                   "x" * 244, "é", "Ａ", "x\x1b[31m")
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
        for value in ("a", "Aa09._:-", "x" * 243):
            _, fields = self.send("--supersedes", value, "--thread", value, "--re", value)
            self.assertEqual(fields["supersedes"], value)
            self.assertEqual(fields["thread"], value)
            self.assertEqual(fields["re"], value)
        self.query()
        self.assertTrue(self.query(compat=True)["complete"])

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

    def watch_writes(self):
        log = self.work / "write-calls"
        self.env["WRITE_PROBE_LOG"] = str(log)
        for name in ("mktemp", "mkdir", "ln", "mv"):
            target = shutil.which(name)
            self.assertIsNotNone(target)
            wrapper = self.tools / name
            wrapper.write_text('#!/bin/sh\n'
                               'printf "%s\\n" ' + shlex.quote(name) + ' >> "$WRITE_PROBE_LOG"\n'
                               'exec ' + shlex.quote(target) + ' "$@"\n')
            wrapper.chmod(0o755)
        return log

    def test_legacy_header_inputs_refused_before_any_write(self):
        log = self.watch_writes()
        cases = (
            ("--re", "prior\nfrom: injected"), ("--re", "prior\rfrom: injected"),
            ("--re", "x" * 244), ("--re", "bad id"), ("--re", "../outside"),
            ("--deadline", "2026-09-30T00:00:00Z\nsupersedes: forged"),
            ("--deadline", "2026-09-30T00:00:00Z\rsupersedes: forged"),
            ("--deadline", "2" * 129),
        )
        for flag, value in cases:
            with self.subTest(flag=flag, value=repr(value)):
                log.unlink(missing_ok=True)
                before = self.snapshot()
                result = self.command("send", "beta", "info", "invalid", flag, value, input="body\n")
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(result.stdout, "")
                self.assertEqual(self.snapshot(), before)
                self.assertFalse(log.exists(), "rejected metadata reached a write primitive")

    def test_invalid_session_refused_on_send_and_reply_before_write(self):
        self.letter("task-a", agent="alpha", **{"from": "beta", "to": "alpha"})
        log = self.watch_writes()
        for value in ("s\nfrom: injected", "s\rfrom: injected", "s" * 65, "bad session", "a/b", "é"):
            for args in (("send", "beta", "info", "invalid"), ("reply", "task-a", "ack", "invalid")):
                with self.subTest(value=repr(value), command=args[0]):
                    log.unlink(missing_ok=True)
                    before = self.snapshot()
                    result = self.command(*args, env=dict(self.env, LETTERBOX_SESSION=value), input="body\n")
                    self.assertNotEqual(result.returncode, 0)
                    self.assertEqual(result.stdout, "")
                    self.assertEqual(self.snapshot(), before)
                    self.assertFalse(log.exists(), "rejected session reached publication or lock creation")

    def test_deadline_exact_utc_and_calendar_validation(self):
        for value in ("2026-09-30", "2026-09-30T00:00:00+00:00", "2026-09-30T00:00:00.0Z",
                      "2026-09-30T00:00:00z", "2026-09-30T24:00:00Z", "2026-09-30T00:60:00Z",
                      "2026-09-30T00:00:60Z", "2026-02-29T00:00:00Z", "1900-02-29T00:00:00Z",
                      "2026-04-31T00:00:00Z", "0000-01-01T00:00:00Z", "2026-13-01T00:00:00Z",
                      "2026-01-00T00:00:00Z"):
            with self.subTest(value=value):
                before = self.snapshot()
                result = self.command("send", "beta", "info", "invalid", "--deadline", value, input="body\n")
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(self.snapshot(), before)
        for value in ("", "2000-02-29T23:59:59Z", "2026-09-30T00:00:00Z", "2028-02-29T00:00:00Z"):
            with self.subTest(valid=value):
                _, fields = self.send("--deadline", value, "--re", "Aa09._:-",
                                      env=dict(self.env, LETTERBOX_SESSION="s" * 64))
                self.assertEqual(fields["deadline"], value)
                self.assertEqual(fields["re"], "Aa09._:-")
                self.assertEqual(fields["session"], "s" * 64)

    def test_invalid_publication_clock_refused_without_letter(self):
        self.letter("task-a", agent="alpha", **{"from": "beta", "to": "alpha"})
        for stamp in ("2026-01-01T00:00:00Z\nfrom: injected", "2026-02-29T00:00:00Z"):
            env, _ = self.clock(stamp)
            for args in (("send", "beta", "info", "invalid"), ("reply", "task-a", "ack", "invalid")):
                with self.subTest(command=args[0], stamp=repr(stamp)):
                    before = self.snapshot()
                    result = self.command(*args, env=env, input="body\n")
                    self.assertNotEqual(result.returncode, 0)
                    self.assertEqual(self.snapshot(), before)
                    self.assertFalse(list(self.box.rglob("*.lifecycle.lock")))

    def test_max_slug_round_trips_ack_and_result(self):
        # id=17-byte time + four '-' + eight hex + sender/type/slug.
        # Reserve '--beta--result' and the 12-byte temporary-name overhead.
        maximum = 255 - 12 - len("--beta--result") - 29 - len("alpha") - len("request")
        parent_path, parent = self.send("--ack", kind="request", slug="s" * maximum)
        original = parent_path.read_bytes()
        self.assertEqual(len(parent["id"].encode("ascii")) + len("--beta--result"), 243)
        for kind in ("ack", "result"):
            result = self.command("reply", parent["id"], kind, "response", input=kind + "\n",
                                  env=dict(self.env, LETTERBOX_AGENT="beta"))
            self.assertEqual(result.returncode, 0, (result.stdout, result.stderr))
            reply_path = self.box / "alpha/inbox" / (parent["id"] + "--beta--" + kind + ".md")
            self.assertEqual(self.header(reply_path)["re"], parent["id"])
        self.assertEqual((self.box / "beta/processed" / parent_path.name).read_bytes(), original)
        self.query()
        self.assertTrue(self.query(compat=True)["complete"])

    def test_over_limit_slug_refused_before_any_write(self):
        cases = (("alpha", "beta", "request"), ("a", "b", "info"),
                 ("sender-long", "recipient-longer", "delegate"))
        initialized = self.command("init", *sorted({agent for row in cases for agent in row[:2]}))
        self.assertEqual(initialized.returncode, 0, initialized.stderr)
        log = self.watch_writes()
        for sender, recipient, kind in cases:
            maximum = 255 - 12 - len("--" + recipient + "--result") - 29 - len(sender) - len(kind)
            with self.subTest(sender=sender, recipient=recipient, kind=kind):
                before = self.snapshot()
                result = self.command("send", recipient, kind, "s" * (maximum + 1), "--ack",
                                      input="body\n", env=dict(self.env, LETTERBOX_AGENT=sender))
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("slug too long: max " + str(maximum) + " characters", result.stderr)
                self.assertEqual(self.snapshot(), before)
                self.assertFalse(log.exists())

    def test_legacy_long_id_reply_reference_and_query(self):
        # Generated with the actual public v0.4.0 writer, synthetic alpha/beta,
        # request/--ack and a 110-character slug; deliberately has no sent field.
        raw = (ROOT / "tests/fixtures/legacy-v040-long-id.md").read_bytes()
        ident = next(line[4:] for line in raw.decode().splitlines() if line.startswith("id: "))
        self.assertEqual(len(ident.encode("ascii")), 151)
        parent_path = self.box / "beta/inbox" / (ident + ".md")
        parent_path.write_bytes(raw)
        for kind in ("ack", "result"):
            result = self.command("reply", ident, kind, "response", input=kind + "\n",
                                  env=dict(self.env, LETTERBOX_AGENT="beta"))
            self.assertEqual(result.returncode, 0, (result.stdout, result.stderr))
        _, fields = self.send("--re", ident, "--supersedes", ident, "--thread", ident)
        self.assertEqual(fields["re"], ident)
        self.assertEqual(fields["supersedes"], ident)
        self.assertEqual(fields["thread"], ident)
        self.assertEqual((self.box / "beta/processed" / parent_path.name).read_bytes(), raw)
        self.assertIn('id: "' + ident + '"', self.query())
        data = self.query(compat=True)
        self.assertTrue(data["complete"])
        self.assertIn(ident, [card["identity"] for card in data["cards"]])

    def test_generated_id_is_bounded_before_temp_creation(self):
        log = self.watch_writes()
        for suffix in ("bad!suffix", "x" * 244):
            # Defense at publication still matters if an external random-byte
            # helper produces malformed output, despite a reply-safe slug.
            tool = self.tools / "od"
            tool.write_text('#!/bin/sh\nprintf "%s" ' + shlex.quote(suffix) + '\n')
            tool.chmod(0o755)
            log.unlink(missing_ok=True)
            before = self.snapshot()
            result = self.command("send", "beta", "info", "topic", input="body\n")
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(self.snapshot(), before)
            self.assertFalse(log.exists())

    def test_inherited_reply_metadata_refused_before_lock(self):
        log = self.watch_writes()
        cases = (("task-a", {"thread": "bad thread"}),
                 ("task-b", {"thread": "x" * 244}),
                 ("task-c", {"from": "../outside"}),
                 ("x" * 240, {}))  # Parent id fits, but the derived reply id does not.
        for ident, overrides in cases:
            with self.subTest(ident=ident[:20], overrides=overrides):
                self.letter(ident, agent="alpha", **dict({"from": "beta", "to": "alpha"}, **overrides))
                log.unlink(missing_ok=True)
                before = self.snapshot()
                result = self.command("reply", ident, "ack", "invalid", input="body\n")
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(self.snapshot(), before)
                self.assertFalse(log.exists())

    def test_legacy_forged_but_valid_field_is_not_authentication(self):
        predecessor = self.letter("predecessor")
        path = self.box / "beta/inbox/old-forged.md"
        path.write_text('---\nid: old-forged\nfrom: alpha\nto: beta\ntype: info\n'
                        're:\npriority: next\nrequires_ack: false\n'
                        'deadline: 2026-09-30\nsupersedes: predecessor\n---\nold writer body\n')
        before = self.snapshot()
        # An old injected but syntactically valid field is indistinguishable
        # from intentional metadata. Queries are not writer-authentication checks.
        self.assertIn('id: "predecessor"', self.query("superseded=yes"))
        data = self.query("superseded=yes", compat=True)
        self.assertEqual(data["cards"][0]["identity"], predecessor.stem)
        self.assertEqual(self.snapshot(), before)

    def test_old_writer_injected_header_fails_closed_without_repair(self):
        self.letter()
        path = self.box / "beta/inbox/old-injected.md"
        path.write_text('---\nid: old-injected\nfrom: alpha\nto: beta\ntype: info\n'
                        're: prior\nfrom: injected\npriority: next\nrequires_ack: false\n'
                        'deadline:\n---\nold writer body\n')
        before = self.snapshot()
        self.assertIn("duplicate_key", self.query(code=2))
        data = self.query(compat=True, code=2)
        self.assertFalse(data["complete"])
        self.assertIsNone(data["complete_counts"])
        self.assertIn("duplicate_key", [d["code"] for d in data["diagnostics"]])
        self.assertTrue(all(c["answered"] == "unknown" for c in data["cards"]))
        self.assertEqual(self.snapshot(), before)

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
