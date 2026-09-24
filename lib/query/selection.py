"""Three-valued selection of already-computed full-scope graph facts."""
from __future__ import annotations

from dataclasses import dataclass
import re

from envelopes import compare_fact, conjunction, publication_time

ALLOWED = frozenset(("from", "to", "type", "thread", "state", "answered", "head",
                     "superseded", "legacy", "since", "until", "slug~"))
ENUMS = {
    "state": ("any", "open", "closed", "unknown"),
    "answered": ("yes", "no", "unknown"),
    "head": ("yes", "no", "unknown"),
    "superseded": ("yes", "no", "head", "unknown"),
    "legacy": ("yes", "no", "any"),
}


class FilterError(ValueError):
    pass


@dataclass(frozen=True)
class Filter:
    name: str
    value: str


@dataclass(frozen=True)
class Decision:
    value: bool | None
    unknown_filters: tuple[str, ...]
    false_filters: tuple[str, ...]


def parse_filters(tokens):
    filters = {}
    for token in tokens:
        key, sep, value = token.partition("=")
        if (not sep or key not in ALLOWED or key in filters or not value
                or len(value) > 4096
                or any(ord(c) < 32 or ord(c) == 127 for c in value)):
            raise FilterError("invalid_filter")
        if key in ENUMS and value not in ENUMS[key]:
            raise FilterError("invalid_filter_value")
        if key in ("since", "until") and publication_time({"sent": value})[0] is None:
            raise FilterError("invalid_filter_time")
        filters[key] = value
    if "head" in filters and "superseded" in filters:
        raise FilterError("conflicting_head_filters")
    if "since" in filters and "until" in filters:
        if publication_time({"sent": filters["since"]})[0] > publication_time({"sent": filters["until"]})[0]:
            raise FilterError("reversed_time_range")
    return tuple(Filter(k, v) for k, v in sorted(filters.items()))


def slug(fact):
    """Strict-v1 display-label derivation; never identity or time authority."""
    record = fact.occurrence
    if record.identity is None:
        return None
    fields = record.fields
    topic = record.identity.split("--", 1)[0]
    topic = re.sub(r"^\d{4}-\d\d-\d\dT\d{6}-", "", topic)
    prefix = fields.get("from", "") + "-" + fields.get("type", "") + "-"
    if topic.startswith(prefix):
        topic = topic[len(prefix):]
    elif "--" in record.identity:
        topic = re.sub(r"^.*?-(?:request|delegate|info|status|blocker|result|ack|nack)-", "", topic, count=1)
    return re.sub(r"-[0-9a-f]{8}$", "", topic)


def decide(fact, filters):
    """No graph construction, filesystem reads, or provenance attestation here.

    A known false predicate excludes even alongside unknown predicates. Unknown
    selection must be reported separately from known exclusion by the caller.
    """
    values = []
    unknown, false = [], []
    for rule in filters:
        key, expected = rule.name, rule.value
        if key in ("from", "to", "type", "thread"):
            value = fact.occurrence.fields.get(key, "") == expected
        elif key in ("answered", "head", "state"):
            value = True if key == "state" and expected == "any" else compare_fact(getattr(fact, key), expected)
        elif key == "superseded":
            target = {"yes": "no", "no": "yes", "head": "yes", "unknown": "unknown"}[expected]
            value = compare_fact(fact.head, target)
        elif key == "legacy":
            value = True if expected == "any" else fact.canonical == (expected == "no")
        elif key in ("since", "until"):
            instant = publication_time(fact.occurrence.fields)[0]
            bound = publication_time({"sent": expected})[0]
            value = None if instant is None else (instant >= bound if key == "since" else instant <= bound)
        elif key == "slug~":
            label = slug(fact)
            value = None if label is None else expected.casefold() in label.casefold()
        else:
            raise FilterError("invalid_filter")
        values.append(value)
        if value is None:
            unknown.append(key)
        elif value is False:
            false.append(key)
    return Decision(conjunction(values), tuple(unknown), tuple(false))
