---
name: handling-mail
description: Use when a Letterbox doorbell arrives, or when working an agent inbox — reading, replying, filing, and keeping the operational view usable
---

# Handling mail

You have a Letterbox inbox. This is how to work it.

## When a doorbell arrives

Run `letterbox check` first — not a directory listing.

`check` is the operational view: open work with live items first, stale work
last, unacknowledged markers, and progress notes with their age. A directory
listing shows you filenames and none of that.

Then `letterbox read <ref>` for the letter itself. A `<ref>` is a full id, a
display id (`timestamp · token`), or a unique 8-hex token.

**Read the reference off the letter. Do not construct it.** Ids are built from
a timestamp, the subject slug and a token, and reconstructing one from a
remembered subject produces a plausible id that does not exist. The error says
"message not found", which reads like a missing letter rather than a wrong
reference.

## Answering

| you are | command |
|---|---|
| accepting work, starting it | `letterbox reply <id> ack <slug>` |
| finished | `letterbox reply <id> result <slug>` |
| declining, or cannot | `letterbox reply <id> nack <slug>` |
| still working, no news needed | `letterbox progress <id> "<one line>"` |

Body from stdin. **ACK is not completion** — it leaves the letter open and
says work has started. Only `result` or `nack` closes it. A request with
`requires_ack: false` may answer once with `result` or `nack` and skip the ACK.

## Filing, and why it matters

A non-task letter closes only when you `letterbox file <ref>`. Nothing files
itself.

**Do this as you go.** Letters that are never filed stay open forever, and an
inbox where everything is open cannot tell you what needs you — at which point
`check` stops being usable and you fall back to listing files, which shows you
none of what it would have.

## Sending

`letterbox send <to> <type> <slug> [--now]`, body from stdin. `--now` rings.

**Ring when you send.** The bell is how the recipient learns the letter
exists; without it a letter sits in a mailbox nobody knows about. Durability
means a failed bell is recoverable rather than a lost message — it does not
mean the bell was unnecessary.

A successful ring means a line reached a surface, never that anyone read it.
`no_live_surface` means you could not reach or validate a usable target from
where you are — not that the recipient has stopped. Read the reason given and
your edition's setup documentation; do not relaunch anything on the strength of
it. The letter has landed regardless.

Submission is opt-in on every edition via `LETTERBOX_<PLATFORM>_SUBMIT=1`. With
it off the behaviour differs by platform — a notification on cmux and Herdr, a
status-line message on tmux, and on Zellij no ring at all.

## Scope and honesty

- `read` is your own inbox only. It will not scan paths or other mailboxes.
- Never send a synthetic or test letter into a real mailbox. If you must probe
  behaviour, aim it at a letter you authored, in a disposable root.
- There are no read receipts and no proof of wake-up. If you need to know
  something was acted on, the evidence is the reply.

## Edition differences — check before you instruct

- `token <8hex>` (glance status: unhandled / filed / unknown) is in all four
  current sources. An older installed copy will reject it as unknown — update
  rather than work around it, and do not infer availability from a version
  number. **Its scope differs**: cmux, Herdr and Zellij look across every
  mailbox; tmux looks only in your own inbox and processed folder.
- `doorbell-line`, `doorbell-parse`: **cmux and Zellij** only.
- Everything else in this skill is present on all four editions.

Do not write instructions that assume a verb, or a scope, the reader's edition
does not have.
