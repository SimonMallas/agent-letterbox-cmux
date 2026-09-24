"""Header-only facts across a full declared Scan, before any selection filter.

No filesystem/transport reads, mutation, timestamp inference or archive authority.
Structural effects require unique eligible endpoints. Ineligible/degraded evidence
can prevent a negative claim without becoming a structural edge itself.
"""
from __future__ import annotations

from collections import defaultdict
from dataclasses import dataclass

from envelopes import LETTER_ID, Occurrence, classify, publication_time
from scanner import Scan

TERMINALS = frozenset(("result", "nack"))


@dataclass(frozen=True)
class GraphIssue:
    code: str
    identifiers: tuple[str, ...]
    source_refs: tuple[str, ...] = ()


@dataclass(frozen=True)
class Fact:
    occurrence: Occurrence
    location: str
    answered: str
    answer_reasons: tuple[str, ...]
    head: str
    head_reasons: tuple[str, ...]
    state: str
    state_reasons: tuple[str, ...]
    reply_route: str

    @property
    def primary_class(self):
        occurrence = self.occurrence
        if occurrence.occurrences > 1:
            return "repeated"
        if not occurrence.structural_identity:
            return "unresolved"
        if occurrence.degraded_edges or occurrence.opaque_thread:
            return "relation_degraded"
        if _bad_sent(occurrence):
            return "time_degraded"
        return occurrence.storage_class

    @property
    def canonical(self):
        return self.primary_class == "canonical"


@dataclass(frozen=True)
class Graph:
    scan: Scan
    facts: tuple[Fact, ...]
    issues: tuple[GraphIssue, ...]
    complete: bool
    dangling_supersedes: tuple[str, ...] | None

    @property
    def scanned(self):
        return len(self.scan.entries)

    @property
    def header_diagnostics(self):
        return self.scanned - len(self.facts)


def _cycles(edges):
    """Functional supersession graph, iterative to avoid recursion-depth limits."""
    finished = set()
    cycles = []
    for start in sorted(edges):
        path, positions = [], {}
        current = start
        while current in edges and current not in finished:
            if current in positions:
                cycle = path[positions[current]:]
                pivot = cycle.index(min(cycle))
                cycles.append(tuple(cycle[pivot:] + cycle[:pivot]))
                break
            positions[current] = len(path)
            path.append(current)
            current = edges[current]
        finished.update(path)
    return tuple(GraphIssue("supersession_cycle", c) for c in sorted(cycles))


def _bad_sent(record):
    return bool(record.fields.get("sent")) and publication_time(record.fields)[1] == "invalid_sent"


def _identity_reason(record):
    if record.occurrences > 1:
        return "repeated_id"
    if "missing_provenance" in record.issues:
        return "missing_provenance"
    return "unresolved_identity"


def _filed(location):
    parts = location.split("/")
    return len(parts) == 2 and parts[1] == "processed"


def evaluate(scan):
    """Compute all occurrence facts; API deliberately accepts no display filters.

    Complete means this declared, non-atomic scope, not global absence/delivery.
    On incomplete enumeration/header reads or a supersession cycle, ALL
    answered/head facts are unknown. Invalid explicit sent degrades time only:
    independently valid identity/relations remain usable, never canonical.
    A known processed location may still report filed/closed. Complete here is
    not a transport or archive capability.
    Reply re/thread are not supersession edges; only supersedes is cycle-checked,
    preserving strict v1's graph type. Unknown thread values remain raw labels.
    """
    entries = tuple(e for e in scan.entries if e.fields is not None and e.issue is None)
    records = classify((e.source_ref, e.basename, e.fields) for e in entries)
    eligible = {r.identity: r for r in records if r.structural_identity}
    known_ids = {r.identity for r in records if r.identity is not None}
    header_complete = scan.complete and len(entries) == len(scan.entries)

    terminals = set()
    uncertain_answers = defaultdict(set)
    superseded = set()
    uncertain_heads = defaultdict(set)
    global_head_reasons = set()
    edges = {}
    dangling = set()

    for record in records:
        fields = record.fields
        relation = fields.get("re", "")
        kind = fields.get("type", "")
        if relation and (kind in TERMINALS or not kind):
            valid_relation = bool(LETTER_ID.fullmatch(relation))
            if record.structural_identity and kind in TERMINALS and valid_relation:
                terminals.add((relation, fields["from"], fields["to"]))
            else:
                sender, recipient = fields.get("from") or None, fields.get("to") or None
                key = (relation if valid_relation else None, sender, recipient)
                if not valid_relation:
                    reason = ("malformed_relation_bounded" if sender and recipient
                              else "malformed_relation_unbounded")
                elif record.occurrences > 1:
                    reason = "ambiguous_terminal"
                else:
                    reason = "unclassified_terminal"
                uncertain_answers[key].add(reason)

        predecessor = fields.get("supersedes", "")
        if not predecessor:
            continue
        if not LETTER_ID.fullmatch(predecessor):
            global_head_reasons.add("malformed_supersedes_global")
        elif record.structural_identity and predecessor in eligible:
            edges[record.identity] = predecessor
            superseded.add(predecessor)
        elif record.structural_identity and predecessor not in known_ids:
            dangling.add(predecessor)
        elif not record.structural_identity:
            uncertain_heads[predecessor].add(
                "ambiguous_edge" if record.occurrences > 1 else "unclassified_superseder")

    # Partial data could hide a repeated identity: do not certify a cycle from it.
    issues = _cycles(edges) if header_complete else ()
    complete = header_complete and not issues
    facts = []
    for entry, record in zip(entries, records):
        fields = record.fields
        relay = "external-bridge" in (fields.get("from"), fields.get("to"))
        route = "external" if relay else "letterbox"
        filed = _filed(entry.location)
        has_terminal = False
        answer_uncertainty = set()
        if not complete:
            reasons = (("incomplete_scan",) if not header_complete
                       else tuple(sorted({issue.code for issue in issues})))
            answered = head = "unknown"
            answer_reasons = head_reasons = reasons
            state, state_reasons = ("closed", ("filed",)) if filed else ("unknown", reasons)
        elif not record.structural_identity:
            reason = _identity_reason(record)
            answered = head = "unknown"
            answer_reasons = head_reasons = (reason,)
            state, state_reasons = ("closed", ("filed",)) if filed else ("unknown", (reason,))
            if relay:
                answer_reasons = ("relay", reason)
        else:
            ident = record.identity
            has_terminal = (ident, fields["to"], fields["from"]) in terminals
            # Known parties bound effects; None is an unknown component, not an ID.
            for target in (ident, None):
                for sender in (fields["to"], None):
                    for recipient in (fields["from"], None):
                        answer_uncertainty.update(uncertain_answers.get((target, sender, recipient), ()))
            if relay:
                answered, answer_reasons = "unknown", ("relay",)
            elif has_terminal:
                answered, answer_reasons = "yes", ("eligible_terminal",)
            elif answer_uncertainty:
                answered, answer_reasons = "unknown", tuple(sorted(answer_uncertainty))
            else:
                answered, answer_reasons = "no", ("no_terminal_in_scope",)

            head_uncertainty = global_head_reasons | uncertain_heads.get(ident, set())
            if ident in superseded:
                head, head_reasons = "no", ("eligible_superseder",)
            elif head_uncertainty:
                head, head_reasons = "unknown", tuple(sorted(head_uncertainty))
            else:
                head, head_reasons = "yes", ("no_superseder_in_scope",)

            if filed:
                state, state_reasons = "closed", ("filed",)
            elif has_terminal:
                state, state_reasons = "closed", ("eligible_terminal",)
            elif answer_uncertainty:
                state, state_reasons = "unknown", tuple(sorted(answer_uncertainty))
            else:
                state, state_reasons = "open", ("no_terminal_in_scope",)
        facts.append(Fact(record, entry.location, answered, answer_reasons, head,
                          head_reasons, state, state_reasons, route))
    return Graph(scan, tuple(facts), issues, bool(complete), tuple(sorted(dangling)) if complete else None)
