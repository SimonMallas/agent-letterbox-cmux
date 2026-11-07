# Mechanical note citation checks

Set `LETTERBOX_DIR`, `LETTERBOX_AGENT`, and `LETTERBOX_NOTES_DIR`, then run:

```
letterbox lint-notes
letterbox lint-notes --json
letterbox lint-notes --baseline
```

`--notes-dir PATH` can override the notes environment variable. Notes are the
non-dot `*.md` files immediately inside that directory (not recursive). Mail
is read through the compatibility-v2 query scanner over all discovered
participants' inbox/processed folders, not outboxes. No letters are changed.
A finding is about this declared scope, not global absence or truth.

Citations use full timestamp-prefixed letter IDs, or `YYYY-MM-DDTHHMMSS · token`.
Token is exactly the doorbell rule: final lowercase eight-hex ID segment when
present, otherwise the first eight hex digits of SHA-256 of the full ID.
Display matching uses both timestamp and token; collisions are never guessed.
Known legacy non-timestamp IDs (letters in scope) are also recognized
literally, with or without code quotes. Any other word without a timestamp is
not a citation, quoted or not: code quotes hold flags, commands and field names
such as `--config`, `lint-notes` and `as-of:`. So an unknown timestamp ID is
reported as ORPHAN, and an unknown legacy ID is not.

Findings (JSON uses lowercase names):

- ORPHAN: no envelope matches a recognized citation in scope.
- AMBIGUOUS: multiple envelope occurrences match a full ID or display citation.
- STALE: the existing query graph says `head=no`.
- DANGLING: the cited envelope's supersedes target is in query's
  `dangling_supersedes` diagnostics.
- UNCURSORED: no whitespace-trimmed line starts `as-of:` within the first 20
  lines (the same normalization as the map check). Invalid cursor
  values are not classified as missing; date validity belongs to the map check.
- FORMATTING: a citation-only line immediately follows nonblank prose. Put the citation on its claim line. This is a mechanical layout
  convention, not semantic detection of what text constitutes a claim.

These checks do not establish entailment, completeness of citations, truth,
permission, or whether a supersedes relation whose query head is unknown has
been resolved. Unreadable notes, malformed baselines and incomplete query
scans fail with exit 2 rather than producing a clean verdict or false orphans.
The JSON names the cause in `reason`, from a fixed set:
`LETTERBOX_NOTES_DIR_unset`, `notes_directory_unreadable`, `unsafe_note`,
`note_not_utf8`, `incomplete_query_scope`, `mail_changed_during_scan`,
`unsafe_baseline`, `invalid_baseline`, `invalid_baseline_key`, `read_error`
or `invalid_input`. If letters arrive or are filed during the scan, lint scans
once more; `mail_changed_during_scan` means they moved during both scans, so
run it again in a quieter moment.
Exit 1 means findings; exit 0 means no new findings under these mechanics.

JSON schema: `letterbox.lint.v1`, with `agent`, `findings`, `baseline`,
`complete`, and `scope`. Each finding has `file` (relative filename), `line`
(1-based), `kind`, `citation` (null for UNCURSORED), and `detail`.

`--baseline` prints findings first, then atomically replaces the notes-local
`.lint-baseline` with the current finding keys. Subsequent runs suppress
existing `(file, citation, kind)` keys, never line numbers, so line insertion
alone does not resurrect a finding. First-run findings are still reported.
A baseline is disposable and is never stored in the letter record. Baseline
refresh explicitly accepts current findings; it is not a correction of them.
