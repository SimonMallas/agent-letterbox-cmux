"""Open loops (view=owed): a named preset over already-computed graph facts.

No second definition of answered: a letter is answered only by the graph's
eligible terminal (result or nack FROM its addressee TO its sender, re: its id).
Owed = an unfiled letter in the agent's own inbox that can obligate (type
request, or requires_ack true). Answered is its tier, not its removal: only
filing takes a letter off the view. Relay letters, whose sender
has no mailbox in the box, are answered by the bridge, not by a Letterbox
reply: the preset reads exactly <agent>/outbox/reply-<id>.md for them, never
the outbox as a folder. That file proves a reply was composed, not delivered.
"""
from __future__ import annotations

from collections import defaultdict
import os
import stat

from envelopes import HeaderError, LETTER_ID, conjunction, publication_time, read_header
from presentation import SCHEMA, _card
from scanner import DIR_FLAGS, FILE_FLAGS

UNPROVEN = "answered (delivery unproven)"


def _relay_reply(root, agent, ident):
    """none | composed | unreadable; descriptor-bound, header only, never writes."""
    fds = []
    try:
        fds.append(os.open(root, DIR_FLAGS))
        for name in (agent, "outbox"):
            fds.append(os.open(name, DIR_FLAGS, dir_fd=fds[-1]))
        fd = os.open("reply-" + ident + ".md", FILE_FLAGS, dir_fd=fds[-1])
        fds.append(fd)
        if not stat.S_ISREG(os.fstat(fd).st_mode):
            return "unreadable"
        with os.fdopen(fd, "rb", buffering=0, closefd=False) as stream:
            fields = read_header(stream)
    except FileNotFoundError:
        return "none"
    except (OSError, HeaderError):
        return "unreadable"
    finally:
        for fd in reversed(fds):
            os.close(fd)
    # A file named for this letter that answers another is not this reply.
    return "composed" if fields.get("re") == ident else "unreadable"


def _deadline(fields, now):
    raw = fields.get("deadline", "")
    if not raw:
        return None, False
    instant = publication_time({"sent": raw})[0]
    if instant is None:
        return None, None
    return instant, instant < now


def owed_document(graph, root, agent, *, limit, now):
    participants = set(graph.scan.participants)
    acks = set()
    for fact in graph.facts:
        record = fact.occurrence
        relation = record.fields.get("re", "")
        if record.structural_identity and record.fields.get("type") == "ack" and LETTER_ID.fullmatch(relation):
            acks.add((relation, record.fields["from"], record.fields["to"]))
    locations = defaultdict(list)
    for fact in graph.facts:
        if fact.occurrence.identity:
            locations[fact.occurrence.identity].append(fact.occurrence.source_ref)
    locations = {key: sorted(value) for key, value in locations.items()}

    rows = []
    for fact in graph.facts:
        fields = fact.occurrence.fields
        if fact.location != agent + "/inbox" or fields.get("to") != agent:
            continue
        sender = fields.get("from", "")
        relay = sender == "external-bridge" or sender not in participants
        if not (relay or fields.get("type") == "request" or fields.get("requires_ack") == "true"):
            continue
        reply = None
        tier = None
        if fact.answered == "yes":
            owed = "yes"
            tier = "ANSWERED"
        elif relay and graph.complete and fact.occurrence.structural_identity:
            reply = _relay_reply(root, agent, fact.occurrence.identity)
            owed = "yes"
            tier = "ANSWERED-UNPROVEN" if reply == "composed" else "UNACKED"
        elif fact.answered == "no" and not relay:
            owed = "yes"
            ack = (fact.occurrence.identity, fields["to"], fields["from"])
            tier = "ACCEPTED-OPEN" if ack in acks else "UNACKED"
        else:
            owed = "unknown"
        instant = publication_time(fields)[0]
        deadline, passed = _deadline(fields, now)
        overdue = conjunction(({"yes": True, "unknown": None}[owed], passed))
        card = _card(fact, locations)
        card.update({
            "owed": owed, "tier": tier, "relay": relay, "relay_reply": reply,
            "note": UNPROVEN if reply == "composed" else None,
            "deadline_utc": deadline.isoformat().replace("+00:00", "Z") if deadline else None,
            "overdue": {True: "yes", False: "no", None: "unknown"}[overdue],
        })
        rows.append(((instant is None, instant or now, fact.occurrence.source_ref), card))

    cards = [card for _, card in sorted(rows, key=lambda row: row[0])]
    shown = cards[:limit] if limit else cards
    count = lambda key, value: sum(card[key] == value for card in cards)
    issues = [{"domain": "scope", "source_ref": i.source_ref, "code": i.code}
              for i in graph.scan.scope_issues]
    issues.extend({"domain": "graph", "code": i.code, "identifiers": list(i.identifiers)}
                  for i in graph.issues)
    return {
        "schema": SCHEMA, "version": 2, "view": "owed", "agent": agent,
        "complete": graph.complete, "partial": not graph.complete,
        "now": now.isoformat().replace("+00:00", "Z"),
        "scope": {
            "participants": list(graph.scan.participants),
            "folder_patterns": list(graph.scan.folder_patterns),
            "relay_reply_file": "<agent>/outbox/reply-<id>.md",
            "outbox_scanned": False,
            "consistency": graph.scan.consistency,
            "whole_tree_absence_claim": False,
        },
        "order": "publication_oldest_first_unknown_time_last",
        "time_semantics": "explicit_header_sent_not_transport_delivery",
        "counts": {
            "owed": count("owed", "yes"), "owed_unknown": count("owed", "unknown"),
            "unacked": count("tier", "UNACKED"), "accepted_open": count("tier", "ACCEPTED-OPEN"),
            "answered": count("tier", "ANSWERED"),
            "answered_unproven": count("tier", "ANSWERED-UNPROVEN"),
            "overdue": count("overdue", "yes"), "overdue_unknown": count("overdue", "unknown"),
            "unknown_time": sum(card["publication_utc"] is None for card in cards),
            "listed": len(cards), "shown": len(shown),
        },
        "limit": limit, "truncated": len(shown) < len(cards),
        "cards": shown, "issues": issues,
    }
