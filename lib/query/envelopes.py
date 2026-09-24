"""Compatibility foundations; no graph verdicts, body reads or filesystem writes.

Compatibility classification is separate from strict query v1.
The caller must supply an unbuffered binary stream at the envelope start.
"""
from __future__ import annotations

from collections import Counter
from dataclasses import dataclass
import datetime as dt
import re
from types import MappingProxyType
from typing import Mapping

# ASCII bytes; 255-byte filenames minus .<id>.tmp.XXXXXX overhead.
LETTER_ID = re.compile(r"[A-Za-z0-9_.:-]{1,243}")
FIELD = re.compile(r"[A-Za-z][A-Za-z0-9_-]*")
MAX_HEADER = 32768
MAX_LINE = 4096
UTC = dt.timezone.utc


class HeaderError(ValueError):
    """A bounded, printable error code, never raw untrusted envelope data."""


def read_header(stream):
    """Stop exactly at the closing delimiter; never ask for the next byte."""
    total = 0

    def line():
        nonlocal total
        raw = stream.readline(MAX_LINE + 1)
        total += len(raw)
        if len(raw) > MAX_LINE or total > MAX_HEADER:
            raise HeaderError("header_limit")
        if not raw:
            raise HeaderError("unterminated_header")
        try:
            text = raw.decode("utf-8").rstrip("\r\n")
        except UnicodeError:
            raise HeaderError("invalid_encoding") from None
        if any(ord(char) < 32 or ord(char) == 127 for char in text):
            raise HeaderError("control_character")
        return text

    if line() != "---":
        raise HeaderError("missing_opening_delimiter")
    fields = {}
    while True:
        text = line()
        if text == "---":
            return fields
        if not text.strip():
            continue
        key, separator, value = text.partition(":")
        if not separator or not FIELD.fullmatch(key):
            raise HeaderError("invalid_field")
        if key in fields:
            raise HeaderError("duplicate_key")
        fields[key] = value.strip()


@dataclass(frozen=True)
class Occurrence:
    source_ref: str
    basename: str
    fields: Mapping[str, str]
    identity: str | None
    storage_class: str
    issues: tuple[str, ...]
    degraded_edges: tuple[str, ...]
    opaque_thread: bool
    occurrences: int
    structural_identity: bool


def classify(rows):
    """Classify every physical (source_ref, basename, parsed fields) occurrence.

    Even an unclassified filename claiming a valid ID joins its repeated group.
    Invalid identities are never repaired from a filename. This does not compute
    answered/head: excluded sources must still supply possible-effect evidence.
    """
    staged = []
    for source_ref, basename, original in rows:
        fields = dict(original)
        raw_id = fields.get("id", "")
        ident = raw_id if LETTER_ID.fullmatch(raw_id) else None
        issues = []
        if ident is None:
            storage = "unresolved"
            issues.append("missing_id" if not raw_id else "invalid_id")
        elif basename == ident + ".md":
            storage = "canonical"
        elif re.fullmatch(re.escape(ident) + r"-[0-9a-f]{8}\.md", basename):
            storage = "alias"
            issues.append("filename_alias")
        else:
            storage = "unresolved"
            issues.append("id_filename_mismatch_unclassified")
        if any(not fields.get(key) for key in ("from", "to", "type")):
            issues.append("missing_provenance")
        degraded = tuple(key for key in ("re", "supersedes")
                         if fields.get(key) and not LETTER_ID.fullmatch(fields[key]))
        opaque = bool(fields.get("thread") and not LETTER_ID.fullmatch(fields["thread"]))
        staged.append((source_ref, basename, fields, ident, storage, issues, degraded, opaque))
    counts = Counter(row[3] for row in staged if row[3] is not None)
    result = []
    for source, name, fields, ident, storage, issues, degraded, opaque in staged:
        count = counts[ident] if ident is not None else 0
        if count > 1:
            issues.append("repeated_id")
        eligible = (ident is not None and count == 1 and storage in ("canonical", "alias")
                    and "missing_provenance" not in issues)
        result.append(Occurrence(source, name, MappingProxyType(fields), ident, storage,
                                 tuple(issues), degraded, opaque, count, eligible))
    return result


def conjunction(predicates):
    """Three-valued AND. Known false excludes even alongside uncertainty."""
    values = tuple(predicates)
    if any(value is False for value in values):
        return False
    if any(value is None for value in values):
        return None
    return True


def compare_fact(actual, expected):
    """Unknown is selectable explicitly, but indeterminate for yes/no filters."""
    if expected == "unknown":
        return actual == "unknown"
    return None if actual == "unknown" else actual == expected


def publication_time(fields, *, id_utc_attested=False):
    """Return (UTC instant or None, basis), never assume a local-time bound.

    Caller attestation must come from the reviewed producer contract/provenance,
    not a current timezone, winter date, filename guess or caller filter flag.
    Relay endpoints without sent remain unspecified even with that attestation.
    """
    raw = fields.get("sent", "")
    if raw:
        try:
            value = dt.datetime.fromisoformat(raw[:-1] + "+00:00" if raw.endswith("Z") else raw)
            if value.tzinfo is None:
                raise ValueError("naive timestamp")
            return value.astimezone(UTC), "sent_utc"
        except (ValueError, OverflowError):
            return None, "invalid_sent"
    if not id_utc_attested or "external-bridge" in (fields.get("from"), fields.get("to")):
        return None, "id_unspecified"
    try:
        value = dt.datetime.strptime(fields.get("id", "")[:17], "%Y-%m-%dT%H%M%S")
    except ValueError:
        return None, "missing_time"
    return value.replace(tzinfo=UTC), "id_utc_attested"
