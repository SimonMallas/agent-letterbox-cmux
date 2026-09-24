"""Synthetic query contracts; no live mailbox, terminal, or network access."""
import hashlib
import io
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
CLI = ROOT / "bin/letterbox"
sys.path.insert(0, str(ROOT / "lib/query"))
from envelopes import HeaderError, read_header
import scanner


class QueryTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.work = Path(self.temp.name).resolve()
        self.box = self.work / "store"
        for agent in ("alpha", "beta"):
            for folder in ("inbox", "processed"):
                (self.box / agent / folder).mkdir(parents=True)
        self.env = dict(os.environ, LETTERBOX_DIR=str(self.box), LETTERBOX_AGENT="alpha")
        # Ensure the CLI uses the interpreter running this test suite.
        self.tools = self.work / "tools"
        self.tools.mkdir()
        (self.tools / "python3").symlink_to(sys.executable)
        self.env["PATH"] = str(self.tools) + os.pathsep + os.environ["PATH"]
        self.env["LETTERBOX_DOORBELL"] = str(ROOT / "adapters/noop.sh")

    def letter(self, ident="request-a", *, agent="beta", folder="inbox", filename=None, **fields):
        values = {"id": ident, "from": "alpha", "to": "beta", "type": "request",
                  "sent": "2026-01-01T12:00:00Z", "requires_ack": "true"}
        values.update(fields)
        path = self.box / agent / folder / (filename or ident + ".md")
        path.write_text("---\n" + "".join(k + ": " + v + "\n" for k, v in values.items())
                        + "---\nBODY-MUST-NOT-APPEAR\n", encoding="utf-8")
        return path

    def command(self, *args, env=None, input=None):
        result = subprocess.run(["/bin/bash", str(CLI), *args], env=env or self.env,
                                input=input, capture_output=True, text=True, timeout=15)
        self.assertNotIn("Traceback", result.stderr)
        return result

    def query(self, *filters, compat=False, code=0):
        result = self.command("query", *(("--compat-v2",) if compat else ()), *filters)
        self.assertEqual(result.returncode, code, (result.stdout, result.stderr))
        self.assertEqual(result.stderr, "")
        self.assertNotIn("BODY-MUST-NOT-APPEAR", result.stdout)
        return json.loads(result.stdout) if compat else result.stdout

    def snapshot(self):
        return {str(p.relative_to(self.box)): hashlib.sha256(p.read_bytes()).hexdigest()
                for p in self.box.rglob("*") if p.is_file() and not p.is_symlink()}

    def test_empty_and_scope(self):
        out = self.query()
        self.assertIn("query-scope v=1 folders=inbox,processed", out)
        self.assertIn("completeness=complete consistency=non-atomic", out)
        self.assertIn("not proof of global absence", out)
        data = self.query(compat=True)
        self.assertEqual(data["schema"], "letterbox.query.compat.v2")
        self.assertTrue(data["query_empty"])
        self.assertFalse(data["scope"]["whole_tree_absence_claim"])
        self.assertEqual(data["scope"]["folder_patterns"], ["inbox", "processed"])

    def test_terminal_graph_precedes_selection(self):
        self.letter()
        self.letter("result-a", agent="alpha", **{"from": "beta", "to": "alpha",
                    "type": "result", "re": "request-a"})
        before = self.snapshot()
        out = self.query("type=request", "answered=yes", "state=closed")
        self.assertIn("count=1 scanned=2", out)
        data = self.query("type=request", "answered=yes", compat=True)
        self.assertEqual(data["observed_counts"]["selected"], 1)
        self.assertEqual(data["cards"][0]["state"], "closed")
        self.assertEqual(self.snapshot(), before)
        self.assertFalse(any(self.box.rglob("*.ack")))
        self.assertFalse(any((ROOT / "lib/query").rglob("__pycache__")))

    def test_wrong_party_terminal_is_not_answer(self):
        self.letter()
        self.letter("wrong", type="result", re="request-a")
        self.assertIn("count=1", self.query("type=request", "answered=no"))
        self.assertEqual(self.query("type=request", compat=True)["cards"][0]["answered"], "no")

    def test_ack_is_not_terminal(self):
        self.letter()
        self.letter("ack-a", agent="alpha", **{"from": "beta", "to": "alpha",
                    "type": "ack", "re": "request-a"})
        (self.box / "beta/inbox/request-a.md.ack").write_text("acked_at: now\n")
        self.assertIn('answered: "no"', self.query("type=request"))
        self.assertEqual(self.query("type=request", compat=True)["cards"][0]["answered"], "no")

    def test_processed_is_closed_not_necessarily_answered(self):
        self.letter(folder="processed")
        self.assertIn('state: "closed"', self.query())
        card = self.query(compat=True)["cards"][0]
        self.assertEqual((card["state"], card["answered"]), ("closed", "no"))

    def test_external_route_is_not_delivery_proof(self):
        self.letter(**{"from": "external-bridge"})
        self.assertIn('answered: "unknown"', self.query())
        card = self.query(compat=True)["cards"][0]
        self.assertEqual((card["answered"], card["reply_route"]), ("unknown", "external"))

    def test_alias_is_explicit_compatibility_only(self):
        self.letter(filename="request-a-deadbeef.md")
        self.assertIn("invalid_envelope", self.query(code=2))
        card = self.query(compat=True)["cards"][0]
        self.assertEqual(card["storage_class"], "alias")
        self.assertFalse(card["canonical"])
        self.assertIn("filename_alias", card["legacy_reasons"])

    def test_duplicate_identity_never_silently_collapses(self):
        self.letter()
        self.letter(folder="processed")
        self.assertIn("duplicate_id", self.query(code=2))
        data = self.query(compat=True)
        self.assertEqual(data["observed_counts"]["repeated"], 2)
        self.assertTrue(all(c["answered"] == "unknown" for c in data["cards"]))

    def test_invalid_filter(self):
        for args in (("state=bad",), ("from=alpha", "from=beta"), ("body=x",),
                     ("since=2026-01-02T00:00:00Z", "until=2026-01-01T00:00:00Z")):
            with self.subTest(args=args):
                self.query(*args, code=2)
                self.assertFalse(self.query(*args, compat=True, code=2)["complete"])

    def test_filters_and_boundaries(self):
        self.letter("2026-01-01T120000-alpha-request-topic-abcd1234", thread="thread-a")
        args = ("from=alpha", "to=beta", "type=request", "thread=thread-a", "slug~=TOPIC",
                "since=2026-01-01T12:00:00Z", "until=2026-01-01T12:00:00Z")
        self.assertIn("count=1", self.query(*args))
        self.assertEqual(self.query(*args, compat=True)["observed_counts"]["selected"], 1)

    def test_supersession_and_cycle(self):
        self.letter()
        self.letter("request-b", supersedes="request-a")
        self.assertIn('id: "request-b"', self.query("superseded=head"))
        self.assertEqual(self.query("head=yes", compat=True)["cards"][0]["identity"], "request-b")
        self.letter(supersedes="request-b")
        self.assertIn("supersession_cycle", self.query(code=2))
        data = self.query(compat=True, code=2)
        self.assertIsNone(data["complete_counts"])
        self.assertTrue(all(c["head"] == "unknown" for c in data["cards"]))

    def test_missing_folder_refuses_completeness(self):
        (self.box / "beta/processed").rmdir()
        self.query(code=2)
        self.assertFalse(self.query(compat=True, code=2)["complete"])

    def test_archive_is_refused_not_read(self):
        self.letter()
        archive = self.box / "beta/archive"
        archive.mkdir()
        (archive / "secret.md").write_text("NEVER-READ-ARCHIVE")
        self.assertIn("unsupported_archive_layout", self.query(code=2))
        data = self.query(compat=True, code=2)
        self.assertEqual(data["observed_counts"]["scanned"], 1)
        self.assertIn("unsupported_archive_layout", json.dumps(data))
        self.assertNotIn("NEVER-READ-ARCHIVE", json.dumps(data))

    def test_outbox_excluded(self):
        outbox = self.box / "beta/outbox"
        outbox.mkdir()
        (outbox / "draft.md").write_text("not an envelope")
        self.assertIn("scanned=0", self.query())
        self.assertEqual(self.query(compat=True)["observed_counts"]["scanned"], 0)

    def test_symlink_ancestor_has_specific_refusal(self):
        ancestor = self.work / "ancestor"
        ancestor.symlink_to(self.work, target_is_directory=True)
        self.env["LETTERBOX_DIR"] = str(ancestor / "store")
        data = self.query(compat=True, code=2)
        self.assertEqual([i["code"] for i in data["issues"]], ["root_component_symlink"])
        self.assertIsNone(data["complete_counts"])

    def test_nondirectory_ancestor_retains_specific_refusal(self):
        ancestor = self.work / "not-a-directory"
        ancestor.write_text("ordinary file")
        self.env["LETTERBOX_DIR"] = str(ancestor / "store")
        data = self.query(compat=True, code=2)
        self.assertEqual([i["code"] for i in data["issues"]], ["root_component_not_directory"])

    def test_leaf_open_refuses_swapped_symlink_before_opening_target(self):
        leaf = self.letter()
        outside = self.work / "outside.md"
        outside.write_bytes(leaf.read_bytes())
        real_open = os.open
        opened = []

        def swap_then_open(name, flags, *, dir_fd):
            leaf.unlink()
            leaf.symlink_to(outside)
            fd = real_open(name, flags, dir_fd=dir_fd)
            opened.append(fd)
            return fd

        parent = real_open(str(leaf.parent), scanner.DIR_FLAGS)
        try:
            result = scanner._Scanner(100)
            with patch.object(scanner.os, "open", side_effect=swap_then_open):
                result.leaf(parent, "beta/inbox", leaf.name)
            # A later signature check is not evidence that NOFOLLOW worked.
            # This specifically requires the kernel to refuse opening the target.
            self.assertEqual(opened, [])
            self.assertEqual(result.entries[0].issue, "leaf_unreadable_or_changed")
            self.assertIsNone(result.entries[0].fields)
        finally:
            os.close(parent)

    def test_leaf_binding_type_guard_rejects_symlink_before_open(self):
        leaf = self.letter()
        outside = self.work / "outside.md"
        outside.write_bytes(leaf.read_bytes())
        leaf.unlink()
        leaf.symlink_to(outside)
        parent = os.open(str(leaf.parent), scanner.DIR_FLAGS)
        try:
            result = scanner._Scanner(100)
            with patch.object(scanner.os, "open", side_effect=AssertionError("opened symlink binding")):
                result.leaf(parent, "beta/inbox", leaf.name)
            self.assertEqual(result.entries[0].issue, "unsafe_leaf")
            self.assertIsNone(result.entries[0].fields)
        finally:
            os.close(parent)

    def test_opened_leaf_type_guard_rejects_swapped_fifo_before_header(self):
        leaf = self.letter()
        real_open = os.open
        opened = []

        def swap_then_open(name, flags, *, dir_fd):
            leaf.unlink()
            os.mkfifo(leaf)
            fd = real_open(name, flags, dir_fd=dir_fd)
            opened.append(fd)
            return fd

        parent = real_open(str(leaf.parent), scanner.DIR_FLAGS)
        try:
            result = scanner._Scanner(100)
            with patch.object(scanner.os, "open", side_effect=swap_then_open), \
                    patch.object(scanner, "read_header", side_effect=AssertionError("read special file")):
                result.leaf(parent, "beta/inbox", leaf.name)
            self.assertEqual(len(opened), 1)  # O_NONBLOCK allows this open.
            # Pin the post-open type guard, not the later signature defence.
            self.assertEqual(result.entries[0].issue, "unsafe_leaf")
            self.assertIsNone(result.entries[0].fields)
        finally:
            os.close(parent)

    def test_layered_leaf_guards_healthy_control(self):
        leaf = self.letter()
        parent = os.open(str(leaf.parent), scanner.DIR_FLAGS)
        try:
            result = scanner._Scanner(100)
            result.leaf(parent, "beta/inbox", leaf.name)
            self.assertIsNone(result.entries[0].issue)
            self.assertEqual(result.entries[0].fields["id"], "request-a")
        finally:
            os.close(parent)

    def test_symlink_leaf_refuses_without_read(self):
        target = self.work / "outside"
        target.write_text("NEVER-READ-OUTSIDE")
        (self.box / "beta/inbox/unsafe.md").symlink_to(target)
        self.query(code=2)
        self.assertFalse(self.query(compat=True, code=2)["complete"])

    def test_symlink_participant_refuses(self):
        (self.box / "gamma").symlink_to(self.box / "beta", target_is_directory=True)
        self.query(code=2)
        self.assertFalse(self.query(compat=True, code=2)["complete"])

    def test_fifo_does_not_block(self):
        os.mkfifo(self.box / "beta/inbox/pipe.md")
        self.query(code=2)
        self.assertFalse(self.query(compat=True, code=2)["complete"])

    def test_malformed_header_keeps_compat_diagnostics(self):
        self.letter()
        (self.box / "beta/inbox/broken.md").write_text("---\nid: broken\n")
        self.query(code=2)
        data = self.query(compat=True, code=2)
        self.assertEqual(data["observed_counts"]["diagnostics"], 1)
        self.assertEqual(data["cards"][0]["answered"], "unknown")

    def test_invalid_time_is_not_inferred_by_compat(self):
        self.letter(sent="invalid")
        self.assertIn("invalid_time", self.query(code=2))
        data = self.query("since=2026-01-01T00:00:00Z", compat=True)
        self.assertEqual(data["observed_counts"]["invalid_sent"], 1)
        self.assertEqual(data["cards"][0]["selection"], "indeterminate")

    def test_explicit_scope_and_enumeration_limit(self):
        self.letter()
        self.letter("request-b")
        data = self.query("--participant", "alpha", compat=True)
        self.assertEqual(data["observed_counts"]["scanned"], 0)
        self.assertEqual(data["scope"]["participants"], ["alpha"])
        self.assertFalse(self.query("--max-names", "1", compat=True, code=2)["complete"])

    def test_isolated_import_and_no_bytecode(self):
        hostile = self.work / "hostile"
        hostile.mkdir()
        (hostile / "json.py").write_text("raise RuntimeError('untrusted import')\n")
        env = dict(self.env, PYTHONPATH=str(hostile))
        result = self.command("query", "--compat-v2", env=env)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(any((ROOT / "lib/query").rglob("__pycache__")))

    def test_absent_python_exact_refusal_and_nonquery_commands(self):
        tools = self.work / "no-python"
        tools.mkdir()
        # Only ordinary shell dependencies, never a Python interpreter.
        for name in ("bash", "dirname", "date", "mkdir", "od", "tr", "awk", "grep",
                     "mktemp", "mv", "basename", "cat", "rmdir", "rm", "shasum", "ln", "sed"):
            target = shutil.which(name)
            self.assertIsNotNone(target, name)
            (tools / name).symlink_to(target)
        env = dict(self.env, PATH=str(tools))
        for mode in ((), ("--compat-v2",)):
            result = self.command("query", *mode, env=env)
            self.assertEqual(result.returncode, 1)
            self.assertEqual(result.stdout, "")
            self.assertEqual(result.stderr, "letterbox: query requires Python 3.9 or newer (python3)\n")
        self.assertEqual(self.command("--version", env=env).returncode, 0)
        self.assertEqual(self.command("init", "gamma", env=env).returncode, 0)
        result = self.command("send", "beta", "info", "without-python", env=env, input="body\n")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.letter("task-a", agent="alpha", **{"from": "beta", "to": "alpha"})
        result = self.command("reply", "task-a", "ack", "accepted", env=env, input="accepted\n")
        self.assertEqual(result.returncode, 0, (result.stdout, result.stderr))
        # Existing v0.4.0 behavior: durable send succeeds, but the bounded
        # doorbell refuses to run an adapter without its Python bounder.
        result = self.command("send", "beta", "info", "ring-without-python", "--now",
                              env=env, input="body\n")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("doorbell-outcome v=1 outcome=no_live_surface reason=adapter_unavailable target=-\n",
                      result.stdout)
        cmux = tools / "cmux"
        cmux.write_text("#!/bin/sh\ncase \"$1\" in\n"
                        "identify) printf '  \"caller\" : {\\n    \"surface_ref\" : \"surface:1\"\\n  }\\n';;\n"
                        "tree) printf 'surface:1\\n';;\nesac\n")
        cmux.chmod(0o755)
        result = self.command("cmux", "register", "alpha", env=env)
        self.assertEqual(result.returncode, 0, (result.stdout, result.stderr))
        self.assertIn("registered: alpha", result.stdout)

    def test_old_python_exact_refusal(self):
        (self.tools / "python3").unlink()
        (self.tools / "python3").write_text("#!/bin/sh\nexit 1\n")
        (self.tools / "python3").chmod(0o755)
        result = self.command("query")
        self.assertEqual(result.returncode, 1)
        self.assertEqual(result.stderr, "letterbox: query requires Python 3.9 or newer (python3)\n")


class HeaderTests(unittest.TestCase):
    def test_body_is_not_requested(self):
        class HeaderOnly(io.BytesIO):
            def readline(self, *args):
                if self.tell() == len(b"---\nid: a\n---\n"):
                    raise AssertionError("read beyond closing delimiter")
                return super().readline(*args)
        self.assertEqual(read_header(HeaderOnly(b"---\nid: a\n---\n")), {"id": "a"})

    def test_duplicate_control_unterminated_and_oversized(self):
        for raw in (b"---\nid: a\nid: b\n---\n", b"---\nid: a\x1b\n---\n",
                    b"---\nid: a\n", b"---\nid: " + b"a" * 4096 + b"\n---\n"):
            with self.subTest(raw=raw[:40]), self.assertRaises(HeaderError):
                read_header(io.BytesIO(raw))


if __name__ == "__main__":
    unittest.main()
