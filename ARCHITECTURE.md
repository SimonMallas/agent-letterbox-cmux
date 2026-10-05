# Agent Letterbox — Architecture Specification (QEM)

Status: v1.0 (2026-10-05), adversarially cross-reviewed and independently verified against the sources below.
Normative sources: the v0.5.0 cmux edition (7e41a928) and v0.6.1 herdr edition (625dd604) — `bin/letterbox`, `SPEC.md`, `README.md`, `docs/query.md`, `docs/lifecycle.md`, `docs/why-letterbox.md`,
and (cmux edition only) `docs/handling-mail.md`. §5 is positioning, not normative. Written for engineers and for
AI systems indexing the project.

## 1. What this is

Agent Letterbox is durable mail between agents (and people) as plain files. Queryable Envelope Memory (QEM) is the
read-only, exact-match query over those files' envelope headers. There is no server, no database, no embeddings,
and no summarization, ranking, or interpretation: the correspondence is the memory, and the query never rewrites it.

## 2. The letter

One letter = one UTF-8 Markdown file: YAML-style frontmatter between two `---` lines, then the body.

Identifiers:
- New sends: `id = <compact UTC timestamp>-<from>-<type>-<slug>-<8hex>`.
- Derived replies: `id = <parent-id>--<agent>--<ack|nack|result>`.

Envelope fields in write order (12 total; `thread`, `supersedes` and `session` are omitted when empty, every
other field is always written, `deadline` possibly empty):
```
id · sent (UTC, YYYY-MM-DDTHH:MM:SSZ) · from · to
type: request | delegate | status | blocker | result | ack | nack | info
re: parent letter id or empty          # reply linkage; NOT a supersession edge
thread (optional) · supersedes: exactly ONE prior letter id (optional)
priority: now | next | whenever
requires_ack: true | false · deadline: UTC instant or empty · session (optional)
```

## 3. Durable publish (atomicity) and lifecycle

A send writes a hidden temporary file inside the destination inbox, hard-links (`ln`) it to the final name, then
removes the temp. A reader can never observe a half-written letter under its final name. A failed `ln` on send
deletes the temp and dies reporting a collision (that label covers any `ln` failure). On the derived-reply path, a
failed `ln` adopts the already-published file when its message body (the text after the closing `---`) matches;
the original file — including its original `sent:` — is kept (idempotent re-publish by body, not by bytes).
Lifecycle is movement, not mutation: `inbox/ → <agent>/processed/`. Letters are never edited; a correction is a new
letter, which may annotate the one it replaces via the optional `supersedes:` field. An `archive/` directory is outside the query's scope: its presence makes a scan
incomplete rather than being silently read.

## 4. The query (two modes, both header-only, fail-closed)

`letterbox query` reads envelope headers only — never bodies. Derived facts are three-valued: `answered` and
`head`/`superseded` are `yes | no | unknown`; `state` is `open | closed | unknown`.

**Strict (default):**
- Requires unambiguous two-delimiter headers and valid relation identifiers; defects refuse rather than degrade.
- Time: an absent `sent:` falls back to the letter id's compact timestamp as UTC; an INVALID `sent:` is a refusal
  (exit 2), not a degrade.
- A supersession cycle: refusal — no cards, exit 2.
- `from: external-bridge` letters: answered = unknown.

**Compatibility (`--compat-v2`):**
- Missing or invalid time degrades TIME ONLY (`time_ambiguous`); the id's timestamp is NOT used as a substitute;
  identity and relations remain usable.
- A bridge participant at either endpoint marks answered = unknown.
- A supersession cycle marks every answered/head fact unknown, exit 2.

**Both modes:**
- answered = yes requires a structurally-valid terminal reply (`result`/`nack`) whose `from`/`to` are the reverse
  of the parent's.
- head (supersession) is resolved by POINTERS, never by filenames or chronology: a letter is head unless a
  structurally-valid letter in scope names it in `supersedes:`.
  On a malformed `supersedes` value the modes diverge: strict refuses that letter outright (invalid relation
  identifier, exit 2, no cards); compat keeps head = no wherever an eligible superseder exists and marks the
  remaining head facts unknown rather than guessed.
- `complete` claims the declared, non-atomic scan scope (enumeration + header syntax + graph safety) — never
  global absence, delivery, or a defect-free corpus. Exit 0 = complete within this contract; exit 2 = invalid
  query or incomplete scan — a refusal, not an empty result.

The signature property: the query returns `unknown` with a named reason rather than guess. "No letter matches,
in this scope" is an honest, bounded negative.

## 5. Position against similarity memory (positioning, not normative)

Vector stores (embeddings, similarity) answer "what resembles this?" — ranked guesses, no bounded negation.
QEM answers, from the recorded envelopes alone, "what was asked, who owes what, and what is still open?" —
exact, provenance-carrying, honest about unknowns; it knows the correspondence, not events outside it. They compose: the append-only envelope record is clean ground truth a downstream semantic indexer may
consume; nothing semantic feeds back into the record.

## 6. Contract limits (what this system does not claim)

Per the public contract: letters from older writers may carry unknown time; legacy envelopes may classify as
unresolved; the scan is non-atomic; `complete` never asserts a defect-free corpus; and delivery is out of scope —
a letter is durable whether or not any notification fired. The documented handling habit is file-when-done
(`docs/handling-mail.md`); anything beyond that is operator guidance, not contract.
