# The Letterbox Method (for agents)

The practice for keeping a team's memory checkable. The person's version is
repository `docs/method.md`. Letters are the record; your notes are your own
authored map over them. Nothing here decides what is true.

## Rules

1. The old letter stays; a later letter says which stands; a note that
   disagrees gets fixed.
2. Never rewrite a letter. If something must be removed (a secret, someone's
   data), it is removed by hand with a letter recording who, what, when and
   why, and every derived copy goes too. There is no command for this.
3. Everything above the record is disposable: notes must rebuild from letters.
4. State is computed, not copied: if a query answers it, don't note it.
5. A scoped empty is not absence. Say where you looked; never say "that
   never happened".
6. The person is a seat, not a supervisor.
7. Never destroy work you didn't create. Copy first, then test, then ask.

## Habits and commands

- Session start: `letterbox check`. Read what is open before acting.
- What you still owe: `letterbox query view=owed to=<you>`. The list shows
  requests and acknowledgement letters still in your inbox, with their
  recorded state (UNACKED, ACCEPTED-OPEN, ANSWERED, ANSWERED-UNPROVEN). A
  letter leaves it when filed. It shows 20 by default (`--limit`); the counts
  cover the rest.
- After handling: `letterbox file <id>`. When your own `check` ends with
  "N non-task letters to review for filing", review them. Don't file a letter
  you haven't read.
- A result cites the letters it rests on, by full id.
- A correction is a new letter: `letterbox send … --supersedes <old-id>`.

## Notes

Keep notes in `LETTERBOX_NOTES_DIR`, one Markdown file per subject, with this
header in the first 20 lines:

```text
as-of: <newest letter id or UTC time this note has read>
threads: <letter threads this note summarises>
covers: <mailboxes or sources read, and what was skipped>
rule: the old letter stays; a later letter says which stands; a note that disagrees gets fixed
```

- Every factual claim cites a letter id on the same line as the claim.
- Your own `check` ends with a map line. `letterbox check --maps` shows, per
  note, how many letters in its threads were sent after its cursor. Newer
  letters mean: read them and refresh the note. They don't prove the note is
  wrong, and a zero doesn't prove it's current.
- `letterbox lint-notes` checks citations mechanically (ORPHAN, AMBIGUOUS,
  STALE, DANGLING, UNCURSORED, FORMATTING). It never checks that a citation
  supports the claim; that is your job.
- Keep: decisions with reasons, preferences, lessons with when they matter.
  Leave out: state a query answers, anything with no letter behind it, copies
  of letter bodies.

## Exit drill (once, before you rely on notes)

Send yourself three letters and note them; delete the notes and caches;
rebuild from the letters alone, outbox included; any fact without a letter
behind it was never recorded. Delete only what letters can rebuild: an
authored review, draft or log is not a cache, so send it as a letter or keep it.
