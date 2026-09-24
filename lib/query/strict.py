"""Strict-v1 header-only query; root is the first positional argument."""
import datetime as dt
import hashlib
import json
import os
import re
import stat
import sys
from contextlib import contextmanager

PARTICIPANT = re.compile(r"[a-z][a-z0-9-]*")
# ASCII bytes; 255-byte filenames minus .<id>.tmp.XXXXXX overhead.
LETTER_ID = re.compile(r"[A-Za-z0-9_.:-]{1,243}")
DIR_FLAGS = os.O_RDONLY | os.O_DIRECTORY | os.O_CLOEXEC | os.O_NOFOLLOW
FILE_FLAGS = os.O_RDONLY | os.O_NONBLOCK | os.O_CLOEXEC | os.O_NOFOLLOW
UTC = dt.timezone.utc
MIN_TIME = dt.datetime.min.replace(tzinfo=UTC)
MAX_HEADER = 32768
MAX_LINE = 4096
participants = []


class QueryError(Exception):
    def __init__(self, code, detail):
        self.code, self.detail = code, detail


def fail(code, detail):
    raise QueryError(code, detail)


def quoted(value):
    return json.dumps(value, ensure_ascii=True, separators=(",", ":"))


def scope(complete):
    print("query-scope v=1 folders=inbox,processed participants=" + quoted(participants)
          + " completeness=" + complete + " consistency=non-atomic")


@contextmanager
def directory(name, parent=None):
    fd = os.open(name, DIR_FLAGS, dir_fd=parent)
    try:
        yield fd
        current = os.stat(name, dir_fd=parent, follow_symlinks=False)
        pinned = os.fstat(fd)
        if (current.st_dev, current.st_ino) != (pinned.st_dev, pinned.st_ino):
            fail("scope_changed", "directory binding changed during scan")
    finally:
        os.close(fd)


def envelope(folder_fd, filename):
    fd = os.open(filename, FILE_FLAGS, dir_fd=folder_fd)
    try:
        if not stat.S_ISREG(os.fstat(fd).st_mode):
            fail("unsafe_leaf", "letter is not a regular file")
        # Unbuffered readline stops at the closing delimiter: never read body.
        with os.fdopen(fd, "rb", buffering=0, closefd=False) as stream:
            total = 0
            def line():
                nonlocal total
                raw = stream.readline(MAX_LINE + 1)
                total += len(raw)
                if len(raw) > MAX_LINE or total > MAX_HEADER:
                    fail("header_limit", "frontmatter exceeds bounded read limit")
                if not raw:
                    fail("invalid_envelope", "unterminated frontmatter")
                text = raw.decode("utf-8").rstrip("\r\n")
                if any(ord(c) < 32 or ord(c) == 127 for c in text):
                    fail("invalid_envelope", "control character in frontmatter")
                return text
            if line() != "---":
                fail("invalid_envelope", "missing opening delimiter")
            fields = {}
            while True:
                text = line()
                if text == "---":
                    break
                if not text.strip():
                    continue
                key, sep, value = text.partition(":")
                if not sep or not re.fullmatch(r"[A-Za-z][A-Za-z0-9_-]*", key):
                    fail("invalid_envelope", "expected flat envelope field")
                if key in fields:
                    fail("duplicate_key", "ambiguous envelope key")
                fields[key] = value.strip()
        ident = fields.get("id", "")
        if not LETTER_ID.fullmatch(ident) or filename != ident + ".md":
            fail("invalid_envelope", "id does not match canonical filename")
        if any(not fields.get(key) for key in ("from", "to", "type")):
            fail("invalid_envelope", "missing envelope provenance")
        for key in ("re", "thread", "supersedes"):
            if fields.get(key) and not LETTER_ID.fullmatch(fields[key]):
                fail("invalid_envelope", "invalid relation identifier")
        return fields
    finally:
        os.close(fd)


def scan(root):
    records = {}
    with directory(root) as root_fd:
        initial_names = sorted(os.listdir(root_fd))
        for name in initial_names:
            # locks is the helper's administrative lease store, not a mailbox.
            if name == "locks" or not PARTICIPANT.fullmatch(name):
                continue
            mode = os.stat(name, dir_fd=root_fd, follow_symlinks=False).st_mode
            if stat.S_ISDIR(mode) or stat.S_ISLNK(mode):
                participants.append(name)
        for participant in participants:
            with directory(participant, root_fd) as participant_fd:
                if "archive" in os.listdir(participant_fd):
                    fail("unsupported_archive_layout", "archive query is not supported")
                for folder in ("inbox", "processed"):
                    with directory(folder, participant_fd) as folder_fd:
                        names = sorted(os.listdir(folder_fd))
                        for name in names:
                            if not name.endswith(".md"):
                                continue
                            fields = envelope(folder_fd, name)
                            ident = fields["id"]
                            if ident in records:
                                fail("duplicate_id", "multiple locations claim id " + ident)
                            fields["_location"] = participant + "/" + folder
                            fields["_folder"] = folder
                            records[ident] = fields
                        if names != sorted(os.listdir(folder_fd)):
                            fail("scope_changed", "mailbox entries changed during scan")
        if initial_names != sorted(os.listdir(root_fd)):
            fail("scope_changed", "root entries changed during scan")
    return records


def instant(raw):
    try:
        value = dt.datetime.fromisoformat(raw[:-1] + "+00:00" if raw.endswith("Z") else raw)
        if value.tzinfo is None:
            raise ValueError("missing timezone")
        return value.astimezone(UTC)
    except (ValueError, OverflowError):
        fail("invalid_time", "expected timezone-qualified ISO-8601 instant")


def sent_time(fields):
    if fields.get("sent"):
        return instant(fields["sent"])
    try:
        return dt.datetime.strptime(fields["id"][:17], "%Y-%m-%dT%H%M%S").replace(tzinfo=UTC)
    except ValueError:
        return None


def slug(fields):
    topic = fields["id"].split("--", 1)[0]
    topic = re.sub(r"^\d{4}-\d\d-\d\dT\d{6}-", "", topic)
    prefix = fields["from"] + "-" + fields["type"] + "-"
    if topic.startswith(prefix):
        topic = topic[len(prefix):]
    elif "--" in fields["id"]:
        # Derived IDs retain the original parent's sender/type prefix.
        topic = re.sub(r"^.*?-(?:request|delegate|info|status|blocker|result|ack|nack)-", "", topic, count=1)
    return re.sub(r"-[0-9a-f]{8}$", "", topic)


def select(records, filters):
    superseded = {r["supersedes"] for r in records.values() if r.get("supersedes")}
    visited = set()
    for start in records:
        path, positions = [], {}
        current = start
        while current in records and current not in visited:
            if current in positions:
                fail("supersession_cycle", "cycle: " + ",".join(path[positions[current]:]))
            positions[current] = len(path)
            path.append(current)
            current = records[current].get("supersedes", "")
        visited.update(path)
    terminal = {(r.get("re"), r["from"], r["to"]) for r in records.values()
                if r["type"] in ("result", "nack") and r.get("re")}
    unknown_time = 0
    selected = []
    for ident, fields in records.items():
        has_terminal = (ident, fields["to"], fields["from"]) in terminal
        # External delivery requires receipts outside this envelope-only scan.
        # Neither silence nor an outbox draft establishes delivery.
        relay = fields["from"] == "external-bridge"
        fields["_reply_route"] = "external" if relay else "letterbox"
        fields["_answered"] = "unknown" if relay else ("yes" if has_terminal else "no")
        closed = fields["_folder"] == "processed" or has_terminal
        fields["_state"] = "closed" if closed else "open"
        fields["_time"] = sent_time(fields)
        fields["_slug"] = slug(fields)
        unknown_time += fields["_time"] is None
        if any(fields.get(key, "") != filters[key] for key in ("from", "to", "type", "thread") if key in filters):
            continue
        if filters["state"] != "any" and fields["_state"] != filters["state"]:
            continue
        if "answered" in filters and fields["_answered"] != filters["answered"]:
            continue
        if "slug~" in filters and filters["slug~"].casefold() not in fields["_slug"].casefold():
            continue
        sup = filters.get("superseded")
        if sup == "yes" and ident not in superseded or sup in ("no", "head") and ident in superseded:
            continue
        if any(fields["_time"] is None or (fields["_time"] < filters[k] if k == "since" else fields["_time"] > filters[k])
               for k in ("since", "until") if k in filters):
            continue
        selected.append(fields)
    selected.sort(key=lambda r: r["id"])
    selected.sort(key=lambda r: r["_time"] or MIN_TIME, reverse=True)
    return selected, unknown_time, len(superseded - records.keys())


def main():
    filters = {}
    allowed = {"from", "to", "type", "thread", "state", "since", "until", "slug~", "superseded", "answered"}
    for arg in sys.argv[2:]:
        key, sep, value = arg.partition("=")
        if not sep or key not in allowed or key in filters or not value:
            fail("invalid_filter", "unknown, repeated or empty filter")
        filters[key] = value
    filters.setdefault("state", "any")
    if filters["state"] not in ("any", "open", "closed"):
        fail("invalid_filter", "invalid state")
    if "superseded" in filters and filters["superseded"] not in ("yes", "no", "head"):
        fail("invalid_filter", "invalid superseded selector")
    if "answered" in filters and filters["answered"] not in ("yes", "no", "unknown"):
        fail("invalid_filter", "invalid answered selector")
    for key in ("since", "until"):
        if key in filters:
            filters[key] = instant(filters[key])
    if "since" in filters and "until" in filters and filters["since"] > filters["until"]:
        fail("invalid_filter", "since is after until")
    records = scan(sys.argv[1])
    selected, unknown, dangling = select(records, filters)
    scope("complete")
    print("query-result count=%d scanned=%d unknown_time=%d dangling_supersedes=%d" % (len(selected), len(records), unknown, dangling))
    for fields in selected:
        ident = fields["id"]
        suffix = re.search(r"[0-9a-f]{8}$", ident)
        token = suffix.group() if suffix else hashlib.sha256(ident.encode()).hexdigest()[:8]
        print("═══ " + ident[:17] + " · " + token)
        for key in ("id", "from", "to", "type", "re", "thread", "supersedes", "priority", "requires_ack", "deadline", "session", "sent"):
            print("    " + key + ": " + quoted(fields.get(key, "")))
        for key in ("state", "answered", "reply_route", "location", "slug"):
            print("    " + key + ": " + quoted(fields["_" + key]))
    if not selected:
        print("query-empty: no matching envelope in stated scope (not proof of global absence)")


try:
    main()
except QueryError as exc:
    scope("incomplete")
    print("query-error code=" + exc.code + " detail=" + quoted(exc.detail))
    sys.exit(2)
except (OSError, UnicodeError) as exc:
    scope("incomplete")
    print("query-error code=unsafe_or_unreadable detail=" + quoted(type(exc).__name__))
    sys.exit(2)
