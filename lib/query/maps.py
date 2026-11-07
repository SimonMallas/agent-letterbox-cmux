#!/usr/bin/env python3
"""Map age at sweep: how far the letters moved past each note's as-of cursor.

Run through letterbox check (one hint line) or letterbox check --maps (one
line per note). Notes are *.md files in LETTERBOX_NOTES_DIR whose top lines
carry `as-of: <ISO-8601 UTC>` and `threads: <id>, <id>, ...` (commas or spaces).
A letter is in a thread as check --thread counts it (its id, thread: or re: is
the thread id); a listed thread no letter is in is named, as a mistyped id would be.
Its time is query's publication rule: the envelope sent:, else unknown, and
unknown-time letters are counted on their own, never as before or after.
Read-only; --maps reads every envelope header in the box, plain check none.
"""
import sys

if __name__ == "__main__" and (not sys.flags.isolated or sys.version_info < (3, 9)):
    print("map: needs Python 3.9 or newer, isolated (python3 -I)")
    raise SystemExit(0)

import argparse
import datetime as dt
import os
import re

sys.path.insert(0, os.path.dirname(os.path.realpath(__file__)))
from envelopes import UTC, publication_time
from scope import collect

HEAD_LINES = 20
CAP = 200
ISO_UTC = re.compile(r"\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d(\.\d+)?(Z|\+00:00)")


def _printable(text):
    return "".join(c if c.isprintable() else "?" for c in text)


def _head(path):
    """(as-of raw or None, thread ids) from the note's first lines."""
    fields = {}
    with open(path, "rb") as stream:
        for _ in range(HEAD_LINES):
            raw = stream.readline(4097)
            if not raw:
                break
            key, sep, value = raw.decode("utf-8", "replace").strip().partition(":")
            if sep and key in ("as-of", "threads"):
                fields.setdefault(key, value.strip())
    # Thread ids hold no spaces, so a space-separated list reads the same as commas.
    threads = [t for t in re.split(r"[,\s]+", fields.get("threads", "")) if t]
    return fields.get("as-of"), threads


def _read(path):
    try:
        return _head(path)
    except OSError:
        return None


def _cursor(raw):
    if raw is None or not ISO_UTC.fullmatch(raw):
        return None
    return publication_time({"sent": raw})[0]


def _age(cursor, now):
    sec = max(0, int((now - cursor).total_seconds()))
    if sec < 3600:
        return "%dm" % (sec // 60)
    if sec < 86400:
        return "%dh" % (sec // 3600)
    return "%dd" % (sec // 86400)


def _plural(n, word):
    return "%s %s%s" % (n, word, "" if n == 1 else "s")


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", required=True)
    parser.add_argument("--notes", required=True)
    parser.add_argument("--summary", action="store_true", help="one hint line; reads no letters")
    args = parser.parse_args(argv)
    try:
        names = sorted(n for n in os.listdir(args.notes) if n.endswith(".md") and not n.startswith("."))
        notes = [(n, _read(os.path.join(args.notes, n))) for n in names
                 if os.path.isfile(os.path.join(args.notes, n))]
    except OSError:
        print("map: notes path %s unreadable" % _printable(args.notes))
        return 0
    if args.summary:
        unreadable = sum(head is None for _, head in notes)
        uncursored = sum(head is not None and head[0] is None for _, head in notes)
        print("map: %s, %d uncursored%s · letterbox check --maps for letters since each cursor"
              % (_plural(len(notes), "note"), uncursored,
                 ", %d unreadable" % unreadable if unreadable else ""))
        return 0

    try:
        scan = collect(args.root)
    except ValueError:
        print("map: letters unreadable at %s" % _printable(args.root))
        return 0
    letters = [e.fields for e in scan.entries if e.fields is not None]
    now = dt.datetime.now(UTC)
    for name, head in notes:
        label = "map " + _printable(name) + ":"
        if head is None:
            print(label, "unreadable")
            continue
        raw, threads = head
        cursor = _cursor(raw)
        if raw is None:
            print(label, "uncursored")
            continue
        if cursor is None:
            print(label, "as-of not ISO-8601 UTC")
            continue
        line = "%s as-of %s (%s)" % (label, raw, _age(cursor, now))
        if not threads:
            print(line, "· no threads listed")
            continue
        since, unknown, capped, empty = set(), set(), False, 0
        for thread in threads:
            found, matched = set(), False
            for fields in letters:
                if thread not in (fields.get("id"), fields.get("thread"), fields.get("re")):
                    continue
                matched = True
                instant = publication_time(fields)[0]
                if instant is None:
                    unknown.add(fields.get("id"))
                elif instant > cursor:
                    found.add(fields.get("id"))
            if len(found) > CAP:
                capped = True
                found = set(sorted(found)[:CAP])
            since |= found
            empty += not matched
        count = "%d+" % len(since) if capped else str(len(since))
        line += " · %s letter%s since in %s" % (count, "" if count == "1" else "s",
                                                _plural(len(threads), "thread"))
        if unknown:
            line += " · %d unknown-time" % len(unknown)
        if capped:
            line += " · capped at %d per thread" % CAP
        # An incomplete scan proves no absence, so it names no empty thread.
        if empty and scan.complete:
            line += " · %s with no letters" % _plural(empty, "thread")
        print(line)
    if not scan.complete:
        print("map: letter scan incomplete; counts may be low")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
