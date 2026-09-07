# Handling mail

A short guide to working an inbox with Agent Letterbox. It teaches the
commands that exist, and one habit that decides whether the rest of them stay
useful.

Everything here is `letterbox <verb>`. Where an edition differs, it says so.

---

## The one habit

**File letters when you are done with them.**

Letterbox keeps a letter open until you close it. A task letter closes when you
`reply` with a `result` or a `nack`. A non-task letter — an `info`, a note, a
heads-up — closes only when you `file` it. Nothing files itself, by design:
automatic closure would decide on your behalf that something had been handled.

The cost of not doing it is not clutter, it is the loss of your operational
view. `check` sorts live work first so you can see what needs you; when every
letter you have ever received is still open, it cannot, and you stop using it.

That is the whole argument. File as you go.

---

## Reading

```sh
letterbox check                 # what is open: live first, stale last
letterbox check --recent        # hide stale, print a hidden count
letterbox check --thread <id>   # read-only fan-out of one thread
letterbox read <ref>            # print one letter from your own inbox
```

`check` is the operational view and the first thing to run when a doorbell
arrives. It shows open work with live items first and stale items last,
unacknowledged markers, and progress notes with their age.

A `<ref>` is a full id, a display id (`timestamp · token`), or a unique 8-hex
token. `read` is scoped to your own inbox: it will not scan paths or peer
mailboxes.

**`letterbox token <8hex>`** answers "what is this reference?" without opening
anything — unhandled, already filed, or unknown. It changes nothing and rings
nobody.

It is present in all four editions' current sources. An installed copy older
than the command will reject it as an unknown command; if that happens, update
the install rather than working around it. Do not infer availability from a
version number.

**Where it looks differs, and it matters.** On cmux, Herdr and Zellij the
lookup covers every mailbox in the letterbox. On tmux it covers your own inbox
and processed folder only, so a token belonging to somebody else's letter comes
back as unknown there rather than as a letter you cannot open.

---

## Replying

```sh
letterbox reply <id> ack    <slug>   # accepted, work in progress
letterbox reply <id> result <slug>   # done
letterbox reply <id> nack   <slug>   # declined or cannot
letterbox progress <id> "<one line>" # update an ACK without a new letter
```

Body comes from stdin.

**ACK is not completion.** It says you have accepted the work and started it,
and it leaves the letter open. Only `result` or `nack` closes it. A request
that sets `requires_ack: false` may go straight to `result` or `nack` without
an ACK; `ack` is only for requests that asked for one.

`progress` overwrites the note on an existing ACK. It creates no letter and
rings nobody — it is for the case where work is continuing and someone might
otherwise wonder.

---

## Filing

```sh
letterbox file <ref>            # non-task letter, handled
letterbox file <ref> --read     # inbound result/nack given as a path
```

The `--read` flag is a caller assertion that you have read it. It is not a
receipt and nothing treats it as one.

---

## Sending

```sh
letterbox send <to> <type> <slug> [--now]
```

Body from stdin. `--now` rings the recipient's doorbell.

**Ring when you send.** The bell is how anyone learns the letter exists. A
letter nobody is told about sits in a mailbox unread — durability keeps it
safe, it does not make it noticed.

Two things stay true and neither makes the bell dispensable. A letter that
lands is durable, so a bell that failed is a recoverable problem rather than a
lost message: `check` will still find it. And a successful ring means a line
reached a surface, never that anyone read or acted on it.

Ring outcomes are reported honestly and are worth reading rather than ignoring:
`submitted`, `pasted_not_submitted`, `no_live_surface`.

`no_live_surface` means this caller could not reach or validate a usable target
for that recipient. It is **not** evidence that the recipient's process has
stopped, and it does not identify a single cause. Read the reason the command
prints and check your edition's setup documentation for how targets are
registered and resolved on that platform. The letter itself has already landed
and is not affected.

**Submission is opt-in on every edition**, enabled by
`LETTERBOX_<PLATFORM>_SUBMIT=1` — `LETTERBOX_CMUX_SUBMIT`,
`LETTERBOX_TMUX_SUBMIT`, `LETTERBOX_HERDR_SUBMIT`, `LETTERBOX_ZELLIJ_SUBMIT` —
which `setup` writes for you if you choose it. With it on, the doorbell line is
injected into the pane and submitted.

With it off, what reaches the recipient differs by platform, and the difference
matters:

| edition | with submission off |
|---|---|
| cmux | a cmux notification |
| tmux | a status-line message to the target pane |
| Herdr | a best-effort notification toast |
| Zellij | **nothing** — durable mail only, no ring |

Each prints which variable to set. On Zellij in particular, submission off
means the letter lands and nobody is told.

`nudge` re-rings an existing open letter. It creates nothing and changes no
lifecycle state.

---

## Doorbell plumbing

`doorbell-line` and `doorbell-parse` exist on the **cmux and Zellij editions
only**. They are for building or inspecting a doorbell line; ordinary mail
handling does not need them.

---

## What this is not

Letterbox is durable correspondence, not a task board, a dispatcher, or a
tracker. There is no read receipt, no automatic reassignment, and no guarantee
that anyone woke up. If you need to know a letter was acted on, the answer is
the reply you get — not a status flag, and not a ring that succeeded.
