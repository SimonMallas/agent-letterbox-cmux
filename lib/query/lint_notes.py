#!/usr/bin/env python3
"""Mechanical citation checks, never claim extraction or entailment."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.realpath(__file__)))
from graph import evaluate
from scope import collect

STAMP = r"\d{4}-\d{2}-\d{2}T\d{6}"
DISPLAY = re.compile(r"(?<![\w:-])(" + STAMP + r")\s*·\s*([0-9a-f]{8})(?![\w])")
FULL = re.compile(r"(?<![\w:.-])" + STAMP + r"-[A-Za-z0-9_:-]+(?:\.[A-Za-z0-9_:-]+)*(?![\w:-])")
QUOTED = re.compile(r"`([A-Za-z0-9_.:-]{1,243})`")
SCHEMA = "letterbox.lint.v1"


def token(ident):
    # Exact doorbell_token_for_id rule: lowercase 8-hex tail, otherwise SHA256.
    tail = ident.rsplit("-", 1)[-1]
    return tail if re.fullmatch(r"[0-9a-f]{8}", tail) else hashlib.sha256(ident.encode()).hexdigest()[:8]


def citations(line, ids):
    found = []
    occupied = []
    for match in DISPLAY.finditer(line):
        found.append((match.start(), match.end(), match.group(1) + " · " + match.group(2), "display"))
        occupied.append(match.span())
    for pattern, mode in ((FULL, "full"), (QUOTED, "quoted")):
        for match in pattern.finditer(line):
            if any(match.start() < end and match.end() > start for start, end in occupied):
                continue
            value = match.group(1) if mode == "quoted" else match.group()
            # Non-timestamp legacy IDs need code quotes to distinguish them
            # from ordinary prose. Quoted plain words are not presumed IDs.
            if mode == "quoted" and value not in ids and "-" not in value:
                continue
            found.append((match.start(), match.end(), value, "full"))
            occupied.append(match.span())
    # Known legacy IDs also resolve literally without timestamp syntax.
    for ident in ids:
        pattern = r"(?<![A-Za-z0-9_.:-])" + re.escape(ident) + r"(?![A-Za-z0-9_.:-])"
        for match in re.finditer(pattern, line):
            if not any(match.start() < end and match.end() > start for start, end in occupied):
                found.append((match.start(), match.end(), ident, "full"))
                occupied.append(match.span())
    return sorted(found)


def lint(notes, graph, agent):
    ids, displays = {}, {}
    for fact in graph.facts:
        ident = fact.occurrence.identity
        if ident is None:
            continue
        ids.setdefault(ident, []).append(fact)
        if re.match(STAMP, ident):
            displays.setdefault(ident[:17] + " · " + token(ident), set()).add(ident)
    findings = []

    def add(path, line, kind, citation, detail):
        findings.append(dict(file=path.name, line=line, kind=kind, citation=citation, detail=detail))

    for path in sorted(notes.iterdir()):
        if path.name.startswith(".") or path.suffix != ".md":
            continue
        if path.is_symlink() or not path.is_file():
            raise ValueError("unsafe_note")
        lines = path.read_text(encoding="utf-8").splitlines()
        if not any(line.strip().startswith("as-of:") for line in lines[:20]):
            add(path, 1, "uncursored", None, "no as-of: header in first 20 lines")
        for number, line in enumerate(lines, 1):
            matches = citations(line, ids)
            for start, end, cite, mode in matches:
                candidates = displays.get(cite, set()) if mode == "display" else {cite} if cite in ids else set()
                if not candidates:
                    add(path, number, "orphan", cite, "no matching envelope in declared scope")
                elif len(candidates) > 1 or sum(len(ids[i]) for i in candidates) > 1:
                    add(path, number, "ambiguous", cite, "multiple envelope occurrences match; not resolved")
                else:
                    fact = ids[next(iter(candidates))][0]
                    if fact.head == "no":
                        add(path, number, "stale", cite, "query head=no")
                    predecessor = fact.occurrence.fields.get("supersedes")
                    if predecessor in (graph.dangling_supersedes or ()):
                        add(path, number, "dangling", cite, "dangling_supersedes: " + predecessor)
                residue = (line[:start] + line[end:]).strip(" \t`[]().")
                previous = lines[number - 2] if number > 1 else ""
                previous_prose = previous
                for pstart, pend, _, _ in reversed(citations(previous, ids)):
                    previous_prose = previous_prose[:pstart] + previous_prose[pend:]
                if (not residue and previous_prose.strip(" \t`[]().") and
                        not previous.startswith(("as-of:", "threads:", "#", "---"))):
                    add(path, number, "formatting", cite, "citation-only continuation; put citation on claim line")
    return dict(schema=SCHEMA, agent=agent, findings=findings, baseline=False,
                complete=graph.complete, scope="all discovered participant inbox/processed folders")


def baseline_key(finding):
    return (finding["file"], finding["citation"], finding["kind"])


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", required=True)
    parser.add_argument("--agent", required=True)
    parser.add_argument("--notes-dir", default=os.environ.get("LETTERBOX_NOTES_DIR"))
    parser.add_argument("--json", action="store_true")
    parser.add_argument("--baseline", action="store_true")
    args = parser.parse_args(argv)
    try:
        if not args.notes_dir:
            raise ValueError("LETTERBOX_NOTES_DIR_unset")
        notes = Path(args.notes_dir)
        if notes.is_symlink() or not notes.is_dir():
            raise ValueError("notes_directory_unreadable")
        graph = evaluate(collect(args.root, None))
        if not graph.complete:
            raise ValueError("incomplete_query_scope")
        result = lint(notes, graph, args.agent)
        all_findings = result["findings"]
        baseline = notes / ".lint-baseline"
        if baseline.is_symlink():
            raise ValueError("unsafe_baseline")
        if baseline.exists():
            data = json.loads(baseline.read_text(encoding="utf-8"))
            if (not isinstance(data, dict) or data.get("schema") != SCHEMA
                    or not isinstance(data.get("keys"), list)):
                raise ValueError("invalid_baseline")
            for key in data["keys"]:
                if (not isinstance(key, list) or len(key) != 3
                        or not isinstance(key[0], str)
                        or not (key[1] is None or isinstance(key[1], str))
                        or not isinstance(key[2], str)):
                    raise ValueError("invalid_baseline_key")
            keys = set(tuple(key) for key in data["keys"])
            result["findings"] = [f for f in all_findings if baseline_key(f) not in keys]
            result["baseline"] = True
        if args.json:
            print(json.dumps(result, ensure_ascii=True, sort_keys=True))
        else:
            print("scope: " + str(args.root) + " — " + result["scope"])
            for f in result["findings"]:
                print(f"{f['file']}:{f['line']}: {f['kind'].upper()}: {f['citation'] or '-'} — {f['detail']}")
            print(f"{len(result['findings'])} finding(s); mechanics only, not entailment")
        if args.baseline:
            fd, temp = tempfile.mkstemp(prefix=".lint-baseline-", dir=notes)
            try:
                with os.fdopen(fd, "w") as output:
                    json.dump(dict(schema=SCHEMA, keys=[baseline_key(f) for f in all_findings]), output)
                    output.flush()
                    os.fsync(output.fileno())
                os.replace(temp, baseline)
            finally:
                if os.path.exists(temp):
                    os.unlink(temp)
        return 1 if result["findings"] else 0
    except (OSError, UnicodeError, ValueError, TypeError, KeyError):
        print(json.dumps(dict(schema=SCHEMA, complete=False, error="lint_input_unreadable_or_invalid")))
        return 2


if __name__ == "__main__":
    if not sys.flags.isolated:
        raise SystemExit("isolated Python required")
    raise SystemExit(main())
