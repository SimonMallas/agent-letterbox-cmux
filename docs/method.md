# The Letterbox Method

*How a team of agents, and one person, keep a shared memory they can check.*
Version 0.7, November 2026. The practice behind Agent Letterbox 0.7.

---

## 1. The shape

Every message between agents, and every message from you (from your phone,
your menu bar or a chat app), is a **letter**: addressed, dated and kept on
disk. Letters are the record. Nothing is edited in place: a correction is a
new letter that names the one it replaces.

Over the record sit two things:

- **QEM**, Queryable Envelope Memory: a read-only query over letter
  envelopes. *What do I still owe? Which version stands? Is there a letter
  about it?* Answers are counted and say where they looked. An empty answer
  is scoped to what was searched. It is never a "no".
- **Notes**, the map. Each agent keeps quick-reference notes: decisions,
  reasons, preferences. Every factual claim cites the letter it rests on.
  Notes carry an as-of cursor, so anyone can ask what has been written since.
  Notes are authored and derived. The letters stay the record.

QEM+ in 0.7 is QEM with the tools that keep notes connected to their letters:
the owed view, the map line, the notes linter and the tidy line.

Letterbox is memory without an automatic memory manager. It doesn't
summarise, embed or judge what a letter means, and it doesn't decide what is
true. A letter can record a mistake, and a note can be wrong. The Method makes
the sources easy to check. It doesn't make them right.

## 2. The rules

1. **The old letter stays; a later letter says which stands; a note that
   disagrees gets fixed.** This is the rule to remember.
2. **Never rewritten; removed only on purpose, with a record.** If something
   must go (a pasted secret, someone's data), remove it by hand and write a
   letter saying who removed what, when and why. Then remove every derived
   copy too: notes, caches, indexes. A rebuild must not bring it back.
   Letterbox has no command for this. It is a practice.
3. **Everything above the record is disposable.** You can delete the notes
   and rebuild them from the letters. A layer that can't survive that doesn't
   belong above the record.
4. **State is computed, not copied.** If a query can answer it, don't copy
   it into a note. Notes hold what the record can't compute: why, not what.
5. **A scoped empty is not absence.** "I found nothing in this mailbox" is an
   honest answer. "That never happened" is not.
6. **The person is a seat, not a supervisor.** You write letters like anyone
   else. The record doesn't rank its authors.
7. **Never destroy work you didn't create.** No checkout, reset or clean on
   changes you can't account for, and no deleting what you didn't write.
   Keep a copy first, then test, then ask.

## 3. The habits, and the 0.7 command for each

| Habit | Command |
|---|---|
| Start of a session: see what is open | `letterbox check` |
| Before taking on more: see what you still owe | `letterbox query view=owed to=<you>` |
| After answering: file what is handled | `letterbox file <id>`; your own `check` ends with "N non-task letters to review for filing" once it counts five or more |
| Keeping notes: see which have newer letters | set `LETTERBOX_NOTES_DIR`; your own `check` ends with a map line, and `letterbox check --maps` shows each note |
| Checking a note's citations | `letterbox lint-notes` |
| Correcting a letter | `letterbox send … --supersedes <old-id>` |

- **Tasks:** acknowledge, work, report. A result cites the letters it rests
  on, by id.
- **Notes:** cite the letter, name the threads, carry the cursor. When the map
  line shows newer letters in a note's threads, read them and refresh the
  note. A newer letter is a reason to review, not proof the note is wrong, and
  a zero is not proof it's current.
- **Disagreement:** write the letter that says which stands. Silence is not
  consensus.

## 4. The note header

Every standing note starts with these lines, within its first 20 lines:

```text
as-of: <the newest letter id or UTC time this note has read>
threads: <the letter threads this note summarises>
covers: <the mailboxes or sources read, and what was skipped>
rule: the old letter stays; a later letter says which stands; a note that disagrees gets fixed
```

`check --maps` reads `as-of:` and `threads:`. No tool reads `covers:` or `rule:`;
those two lines are for whoever reads the note. `lint-notes` checks each
citation mechanically: a cited id with no letter in scope, more than one
match, a letter that has been superseded or whose supersedes target is
missing, a missing cursor, or a citation on its own line after the claim. It
never judges whether a citation supports the claim.

Keep in a note: decisions and their reasons, preferences and constraints, and
lessons with a line saying when they matter. Keep out: state a query can
answer, anything with no letter behind it, and copies of letter bodies.

## 5. Two machines, one rule

A second machine may copy letters in. It never rewrites one, and every letter
has one home. Crossing machines is delivery with a receipt, not replication.

## 6. The exit

Nothing here locks you in. The letters are plain Markdown in plain folders,
readable with `cat`. Run this drill once before you rely on your notes:

1. Send yourself three letters, and take notes that cite them.
2. Delete the notes and any cache.
3. Rebuild the notes from the letters alone, your outbox included: your
   replies are letters too.
4. Compare. A fact in the new notes with no letter behind it was never
   recorded. That's cheap to fix now.

Delete only what can be rebuilt from letters. An authored piece of work (a
review, a draft, a running log) is not a cache: send it as a letter first, or
keep it. Instructions that matter should arrive as letters, so the record can
show why you acted.

---

*The Method is a practice, not a package. It needs Agent Letterbox (any
edition), and optionally Agent Letter Bridge for a person on a phone.*
