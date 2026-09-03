#!/usr/bin/env python3
"""Print path:line:pat when a forbidden phrase matches after whitespace collapse.

Line-based grep misses 'shared\\nbrain'. Collapse all whitespace to a single
space, then search. Line number is the first line containing the phrase's
first word (so mutation gates still see file:line).

Exit 0 on a successful scan (hits print to stdout; no hits is silent).
Exit 1 on errors. Callers must not swallow a non-zero exit.
"""
from __future__ import annotations

import re
import sys


def scan(path: str, patterns: list[str]) -> int:
    try:
        raw = open(path, "rb").read()
    except OSError as exc:
        print(f"{path}:0:error {exc}", file=sys.stderr)
        return 1
    if b"\0" in raw[:8192]:
        return 0
    text = raw.decode("utf-8", "replace")
    norm = re.sub(r"\s+", " ", text).lower()
    lines = text.splitlines()
    for pat in patterns:
        if not pat or pat.lower() not in norm:
            continue
        first = pat.split()[0].lower()
        ln = 1
        for i, line in enumerate(lines, 1):
            if first in line.lower():
                ln = i
                break
        print(f"{path}:{ln}:{pat}")
    return 0


if __name__ == "__main__":
    if len(sys.argv) < 3:
        sys.exit(0)
    try:
        sys.exit(scan(sys.argv[1], sys.argv[2:]))
    except Exception as exc:
        print(f"{sys.argv[1]}:0:error {exc}", file=sys.stderr)
        sys.exit(1)
