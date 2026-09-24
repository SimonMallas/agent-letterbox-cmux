#!/usr/bin/env python3
"""Explicit compatibility-v2 query; no publication, ring or archive mutation verbs.

Run through letterbox query --compat-v2 [key=value ...].
The isolated interpreter imports only this entrypoint's trusted package directory
plus its normal isolated standard-library/site paths, never cwd/PYTHONPATH.
"""
import sys

if __name__ == "__main__" and not sys.flags.isolated:
    print('{"schema":"letterbox.query.compat.v2","complete":false,"error":"isolated_python_required"}')
    raise SystemExit(2)

import argparse
import json
import os

# Required with -I for this separately staged, not site-installed module set.
sys.path.insert(0, os.path.dirname(os.path.realpath(__file__)))
from graph import evaluate
from presentation import SCHEMA, document
from scope import collect
from selection import FilterError, parse_filters


class UsageError(ValueError):
    pass


class Parser(argparse.ArgumentParser):
    def error(self, message):
        # Do not echo raw command arguments, filesystem errors or tracebacks.
        raise UsageError("invalid_arguments")


def main(argv=None):
    parser = Parser(description=__doc__)
    parser.add_argument("--root", required=True, help="absolute non-symlink letter store directory")
    parser.add_argument("--participant", action="append", help="repeat for an explicit scope; default discovers root names")
    parser.add_argument("--max-names", type=int, default=100000, help="per-directory bound, 1..100000")
    parser.add_argument("--version", action="version", version="letterbox.query.compat.v2")
    parser.add_argument("filters", nargs="*", metavar="key=value")
    try:
        args = parser.parse_args(argv)
        rules = parse_filters(args.filters)
        try:
            result = collect(args.root, args.participant, max_names=args.max_names)
        except ValueError:
            raise UsageError("invalid_scope") from None
        payload = document(evaluate(result), rules, discovery=args.participant is None)
    except (UsageError, FilterError) as error:
        payload = {"schema": SCHEMA, "complete": False, "error": str(error)}
    print(json.dumps(payload, ensure_ascii=True, sort_keys=True, separators=(",", ":")))
    return 0 if payload["complete"] else 2


if __name__ == "__main__":
    raise SystemExit(main())
