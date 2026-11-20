"""Format gate G for the Python readers.

Absent, or the exact bytes flat-v1 / flat-v1\\n, proceeds. Anything else exits 1
with the shell gate's stderr line and writes no stdout. The mark is not followed.

SHOWN rule, same as format_shown in bin/letterbox: after at most one trailing
newline is removed, name the bytes only when they are 1..64 of printable ASCII
(0x20-0x7E) with no single quote and no backslash. Anything else, including a
longer mark, is unreadable. 64 is the read cap and the naming cap. The shell
used to stop at 31 because od starred identical lines; that was a parser bug,
not a reason to call a safe 64-byte value unreadable.

This is one read of the mark, not a barrier against a later swap.
"""

import os
import stat
import sys

MARK_NAME = "format.mark"
MARK_MAX = 64
_ACCEPT = (b"flat-v1", b"flat-v1\n")
_ACTION = "this release reads flat-v1 only, use a release that supports the box format"


def shown(data):
    if not isinstance(data, (bytes, bytearray)):
        return "unreadable"
    raw = bytes(data)
    if raw.endswith(b"\n"):
        if raw.count(b"\n") != 1:
            return "unreadable"
        raw = raw[:-1]
    if not raw:
        return "unreadable"
    for byte in raw:
        if byte < 0x20 or byte > 0x7E or byte in (0x27, 0x5C):
            return "unreadable"
    return "'" + raw.decode("ascii") + "'"


def message(data):
    return "letterbox: format refusal: box format is %s; %s\n" % (shown(data), _ACTION)


def refuse(data):
    sys.stderr.write(message(data))
    raise SystemExit(1)


def check(root):
    """Refuse a bad mark. Return when the box may be read. Do not list it."""
    if not isinstance(root, str) or not root or "\0" in root or not os.path.isdir(root):
        return
    mark = os.path.join(root, MARK_NAME)
    try:
        info = os.lstat(mark)
    except FileNotFoundError:
        return
    except OSError:
        refuse(None)
    if stat.S_ISLNK(info.st_mode) or not stat.S_ISREG(info.st_mode):
        refuse(None)
    if info.st_size > MARK_MAX:
        refuse(None)
    flags = os.O_RDONLY | getattr(os, "O_CLOEXEC", 0) | getattr(os, "O_NOFOLLOW", 0)
    try:
        fd = os.open(mark, flags)
    except OSError:
        refuse(None)
    try:
        data = os.read(fd, MARK_MAX)
    finally:
        os.close(fd)
    if data in _ACCEPT and len(data) == info.st_size:
        return
    refuse(data if info.st_size <= MARK_MAX else None)
