"""Versioned JSON projection. Complete counts never describe a partial graph."""
from collections import Counter, defaultdict

from envelopes import publication_time
from selection import decide, slug

SCHEMA = "letterbox.query.compat.v2"
HEADER_FIELDS = ("id", "from", "to", "type", "re", "thread", "supersedes", "priority",
                 "requires_ack", "deadline", "session", "sent")


def _card(fact, locations):
    record = fact.occurrence
    instant, basis = publication_time(record.fields)
    degraded = (list(record.degraded_edges) + (["thread"] if record.opaque_thread else [])
                + (["sent"] if basis == "invalid_sent" else []))
    return {
        "source_ref": record.source_ref,
        "fields": {key: record.fields.get(key, "") for key in HEADER_FIELDS},
        "identity": record.identity,
        "primary_class": fact.primary_class,
        "storage_class": record.storage_class,
        "canonical": fact.canonical,
        "legacy_reasons": list(record.issues) + ["invalid_" + key for key in record.degraded_edges]
                          + (["opaque_thread"] if record.opaque_thread else [])
                          + (["invalid_sent"] if basis == "invalid_sent" else []),
        "structural_participation": ("none" if not record.structural_identity or fact.primary_class == "unresolved"
                                     else "fields-voided" if degraded else "full"),
        "voided_fields": degraded,
        "location": fact.location,
        "locations": locations.get(record.identity, [record.source_ref]) if record.identity else [record.source_ref],
        "duplicate_group": record.identity if record.occurrences > 1 else None,
        "occurrences": record.occurrences,
        "state": fact.state, "state_reasons": list(fact.state_reasons),
        "answered": fact.answered, "answer_reasons": list(fact.answer_reasons),
        "head": fact.head, "head_reasons": list(fact.head_reasons),
        "reply_route": fact.reply_route,
        "time_basis": basis,
        "publication_utc": instant.isoformat().replace("+00:00", "Z") if instant else None,
        "time_ambiguous": instant is None,
        "slug": slug(fact),
    }


def document(graph, filters=(), *, discovery=False):
    """One accounting category per encountered leaf; issues are NOT extra leaves.

    cards includes selected and explicitly indeterminate rows. nonselected counts
    both known-excluded and indeterminate (with explicit subcounts). Unresolved
    records are diagnostics, never silently discarded by a display predicate.
    Scope/graph failures have their own issue array, not fabricated leaf counts.
    """
    locations = defaultdict(list)
    for fact in graph.facts:
        if fact.occurrence.identity:
            locations[fact.occurrence.identity].append(fact.occurrence.source_ref)
    locations = {key: sorted(value) for key, value in locations.items()}
    cards, diagnostics = [], []
    selected = excluded = indeterminate = 0
    classes = Counter(f.primary_class for f in graph.facts)
    # Warnings are field observations, NOT additional physical occurrences. Emit
    # one per affected record even when its card is hidden or its ID repeats.
    field_warnings = [
        {"code": "invalid_sent", "field": "sent", "identity": f.occurrence.identity,
         "source_ref": f.occurrence.source_ref}
        for f in sorted(graph.facts, key=lambda f: f.occurrence.source_ref)
        if publication_time(f.occurrence.fields)[1] == "invalid_sent"
    ]
    for fact in sorted(graph.facts, key=lambda f: f.occurrence.source_ref):
        if fact.primary_class == "unresolved":
            diagnostics.append({"code": "unresolved_envelope", "record": _card(fact, locations),
                                "source_ref": fact.occurrence.source_ref})
            continue
        decision = decide(fact, filters)
        if decision.value is False:
            excluded += 1
            continue
        card = _card(fact, locations)
        card["selection"] = "selected" if decision.value is True else "indeterminate"
        card["unknown_filters"] = list(decision.unknown_filters)
        if decision.value is True:
            selected += 1
        else:
            indeterminate += 1
        cards.append(card)
    diagnostics.extend({"source_ref": e.source_ref, "code": e.issue or "missing_header"}
                       for e in graph.scan.entries if e.fields is None or e.issue is not None)
    diagnostics.sort(key=lambda d: d["source_ref"])
    issues = [{"domain": "scope", "source_ref": i.source_ref, "code": i.code}
              for i in graph.scan.scope_issues]
    issues.extend({"domain": "graph", "code": i.code, "identifiers": list(i.identifiers),
                   "source_refs": list(i.source_refs)} for i in graph.issues)
    unknown_time = graph.scanned - sum(publication_time(f.occurrence.fields)[0] is not None for f in graph.facts)
    observed = {
        "count": selected, "scanned": graph.scanned, "selected": selected,
        "nonselected": excluded + indeterminate, "nonselected_known": excluded,
        "indeterminate": indeterminate, "cards": len(cards), "diagnostics": len(diagnostics),
        "issues": len(issues), "unknown_time": unknown_time,
        "invalid_sent": len(field_warnings),
        "alias": classes["alias"], "unclassified": classes["unresolved"],
        "relation_degraded": classes["relation_degraded"], "repeated": classes["repeated"],
        "canonical": classes["canonical"], "time_degraded": classes["time_degraded"],
        "conflict_ids": len({f.occurrence.identity for f in graph.facts if f.occurrence.occurrences > 1}),
    }
    assert observed["scanned"] == selected + observed["nonselected"] + len(diagnostics)
    return {
        "schema": SCHEMA, "version": 2, "complete": graph.complete, "partial": not graph.complete,
        "scope": {
            "participants": list(graph.scan.participants),
            "participant_selection": "discovered_matching_root_names" if discovery else "explicit",
            "discovery_pattern": "[a-z][a-z0-9-]* except locks" if discovery else None,
            "folder_patterns": list(graph.scan.folder_patterns),
            "leaf_pattern": graph.scan.leaf_pattern, "direct_leaves_only": graph.scan.direct_leaves_only,
            "enumeration_header_complete": graph.scan.complete,
            "completeness_basis": graph.scan.completeness_basis,
            "consistency": graph.scan.consistency,
            "whole_tree_absence_claim": False,
        },
        "filters": {f.name: f.value for f in filters},
        "order": "source_ref_lexical_not_chronological", "time_ambiguous": bool(unknown_time),
        "time_semantics": "explicit_header_sent_not_transport_delivery",
        "observed_counts": observed,
        "complete_counts": dict(observed) if graph.complete else None,
        "dangling_supersedes": list(graph.dangling_supersedes) if graph.dangling_supersedes is not None else None,
        "query_empty": graph.complete and not cards and not diagnostics,
        "cards": cards, "diagnostics": diagnostics, "issues": issues,
        "field_warnings": field_warnings,
    }
