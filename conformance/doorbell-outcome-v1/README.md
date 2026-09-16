# doorbell-outcome-v1 fixtures

Canonical home: **agent-letterbox-cmux**
`conformance/doorbell-outcome-v1/` (ruling 4). Other editions and Bridge
vendor a frozen snapshot of this directory. CI never fetches.

Coverage is **representative**, not every legal triple.

## Vendor allowlist

```
README.md
accepted.tsv
rejected.tsv
parse-cases.tsv
doorbell-line-accepted.tsv
doorbell-line-rejected.tsv
SHA256SUMS
```

Nothing else ships. Do not vendor `private-stack-prose.tsv` or
`legacy-prose.tsv` from the drafting workspace.

Public files: no private paths, seat names, real IDs, or private-tool outcome
prose.

## Files

`accepted.tsv` — representative legal outcome lines (rev4 adds `unconfirmed`
and charset-legal unknown `future_token`; no retry).
`rejected.tsv` — grammar + illegal triples.
`parse-cases.tsv` — stdout/stderr/exit/retry consumer cases. `\n` encodes
newlines (the same escaping applies wherever a TSV needs a control
character). Public wording only (edition adapters, not private-tool outcome
prose).
`doorbell-line-accepted.tsv` / `doorbell-line-rejected.tsv` — ruling 5
doorbell-line grammar, including `from <sender>` and the still-valid old
shape.

A doorbell **line** (`📬 …`) is never an outcome line.
