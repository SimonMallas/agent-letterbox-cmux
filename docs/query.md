# Queryable envelope memory

`letterbox query` reads envelope headers, not message bodies. It does not send,
ring, acknowledge, file, archive, update an index, or change letters. It uses the
same `LETTERBOX_DIR` / configured default directory as other commands. No agent
identity is required. Use an absolute, non-symlink directory path for queries;
compatibility mode refuses symlinks in any root path component.

Query requires **Python 3.9 or newer**, using only the standard library. Other
commands have no new Python requirement. Missing or older `python3` exits 1 with
exactly this stderr line and no stdout:

```text
letterbox: query requires Python 3.9 or newer (python3)
```

## Strict-v1 (default)

```bash
letterbox query
letterbox query from=planner to=reviewer type=request state=open
letterbox query thread=thread-id answered=no 'slug~=design'
letterbox query superseded=head since=2026-01-01T00:00:00Z
```

Filters are `from`, `to`, `type`, `thread`, `state=any|open|closed`,
`answered=yes|no|unknown`, `superseded=yes|no|head`, `since`, `until`, and
`slug~`. Repeat or empty filters are errors. Time bounds require a timezone and
are inclusive. Slug substring matching is case-insensitive. Default state is
`any`.

Output starts with `query-scope v=1` and names the participants, folders,
completeness, and non-atomic consistency. Envelope cards follow the counts.
Strict mode requires unique canonical filenames (`<id>.md`) and flat,
two-delimiter headers with unambiguous fields and valid relation identifiers.
An unsafe/unreadable leaf, malformed envelope, repeated identity, missing folder,
or supersession cycle makes the query fail closed (exit 2). No partial cards are
presented as complete results.

Strict ordering is newest envelope time first, then ID. When `sent` is absent,
strict mode retains the UTC compact-ID fallback; it does not consult mtime.

## Explicit compatibility-v2

```bash
letterbox query --compat-v2
letterbox query --compat-v2 type=request answered=unknown
letterbox query --compat-v2 --participant planner --participant reviewer legacy=yes
```

This produces JSON with schema `letterbox.query.compat.v2`, not strict-v1 cards.
It accounts for aliases, repeated IDs, unresolved identity, degraded relations,
and unknown timestamps instead of silently treating them as canonical letters.
Filters also include `head=yes|no|unknown`, `legacy=yes|no|any`, and explicit
`unknown` selectors for `state` and `superseded`. `head` and `superseded` cannot
be combined. `--max-names N` bounds each directory enumeration (1..100000);
exceeding it denies completeness, rather than claiming no matches.

Compatibility output uses source-reference order, not chronological order.
Only an explicit valid `sent` supplies publication time. An ID or filesystem
timestamp is not a substitute. Letters produced by an older writer without
`sent` therefore have unknown time; time-filter matches may be indeterminate.
Cards distinguish selected from indeterminate rows, and diagnostics remain
visible even when a display predicate excludes other cards.

`complete` describes enumeration/header syntax and graph safety in the declared
scope, **not a defect-free corpus**. A complete result may still contain aliases,
repeated IDs, diagnostics, or unknown facts. `complete_counts` is null on an
incomplete scan; `observed_counts` reports only observed material. Exit 0 means
complete within this contract, not successful delivery. Exit 2 means an invalid
query or incomplete scan.

## Shared boundaries

- The graph is evaluated before display filters. A hidden matching result can
  still close a visible request. ACK is not terminal; result and nack are.
- An answer requires reversed sender/recipient provenance, not just a `re` value.
  A filed letter is closed but not necessarily answered.
- `external-bridge` is the reserved synthetic bridge participant. Its reply route
  is `external`; ordinary participants use `letterbox`. No transport receipts are
  consulted. Strict mode marks letters *from* that participant as answer-unknown;
  compatibility mode conservatively applies that rule to either endpoint.
- Scans cover direct `*.md` leaves in each participant's `inbox` and `processed`.
  `locks`, outbox drafts, and ordinary sidecars are not inbound letters.
- **Archive traversal and an archive verb are not supported.** A participant's
  `archive` entry makes either mode incomplete; its contents are not read.
- Header reads are bounded and stop at the closing delimiter. Compatibility mode
  additionally reports observed directory/leaf changes. Neither mode is an atomic
  snapshot, a global-absence proof, or a transport-delivery receipt.
- No writer validation or send-side behavior is added by this command.

Validation uses disposable synthetic mailboxes, including refusal and negative
controls. Passing these tests does not qualify a live adapter, a private corpus,
hardware crash durability, or a platform that has not run the tests.
