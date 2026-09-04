# Letter lifecycle (v0.2)

One page for the four verbs that change a letter's state.

## Mental model

```text
[sender publishes letter]
        ↓
 recipient inbox (needs attention)
        ↓
   read + classify
        ↙              ↘
   TASK letter          NON-TASK letter
   requires_ack=true    requires_ack=false
        ↓                      ↓
 non-terminal ACK            file
 (stays in inbox)              ↓
        ↓                  processed/
 terminal NACK / RESULT
        ↓
   processed/
```

Doorbell = wake-up only. Without a bell, nobody is told. Inbox file = source of truth.

## Verbs

| Verb | When | Effect on original letter |
|---|---|---|
| `letterbox reply <id> ack` | Accept a task | Publish ack to sender; write `.md.ack`; **leave letter in inbox** |
| `letterbox reply <id> nack` | Decline a task | Publish nack; move letter to `processed/`; clear sidecar |
| `letterbox reply <id> result` | Finish a task | Publish result; move letter to `processed/`; clear sidecar |
| `letterbox file <id>` | Non-task only | Move letter to `processed/`; no reply |

`letterbox check` is read-only. It labels task letters `[UNACKED]` or `[ACCEPTED]` and never counts `.md.ack` files as mail.

## Happy path

```bash
# planner → reviewer (task)
printf '%s\n' 'GOAL: Review src/auth.ts
DONE-WHEN: Write findings to stdout.' |
  LETTERBOX_AGENT=planner letterbox send reviewer delegate auth-review --ack --now

# reviewer accepts (WIP)
printf '%s\n' 'ACK: starting review.' |
  LETTERBOX_AGENT=reviewer letterbox reply <id> ack auth-review --now

# optional progress (does not close the task)
printf '%s\n' 'Still reading tests.' |
  LETTERBOX_AGENT=reviewer letterbox send planner info auth-review-progress --re <id>

# reviewer finishes (terminal)
printf '%s\n' 'RESULT: one high finding; details in body.' |
  LETTERBOX_AGENT=reviewer letterbox reply <id> result auth-review --now
```

## NACK path

```bash
printf '%s\n' 'NACK: out of scope for this agent.' |
  LETTERBOX_AGENT=reviewer letterbox reply <id> nack auth-review --now
```

## Non-task path

```bash
printf '%s\n' 'Deploy window is 18:00 UTC.' |
  LETTERBOX_AGENT=planner letterbox send builder info deploy-window

LETTERBOX_AGENT=builder letterbox file <id>
```

## Guard rails

- `file` refuses `requires_ack: true` — send terminal `nack`/`result` instead.
- Legacy `done --reply` refuses a letter that already has `.md.ack` — use `reply … result|nack`.
- Do not put GOAL/DONE-WHEN in doorbell text.
- Do not archive after ACK only.
- Do not embed a new task inside a `result`; send a new letter.

## Stdin bodies (heredoc safety)

The helper reads the **body only** from stdin and writes frontmatter itself.

```bash
# Preferred — literal body, no shell expansion surprises
printf '%s\n' 'ACK: I will take this.' | letterbox reply <id> ack my-slug

# Also fine when you need multiple lines without expansion
printf '%s\n' 'RESULT: done.' 'evidence: tests/green' | letterbox reply <id> result my-slug
```

Avoid unquoted heredocs (`<<EOF`) for bodies that may contain `$var`, `$(…)`, or backticks. Those expand in the shell before Letterbox runs. If you use a heredoc, quote the delimiter (`<<'EOF'`).

## Crash safety

Publish happens before local archive. If a process dies mid-close:

- a published reply may already exist — safe to retry the same terminal reply;
- an open task may still sit in `inbox/` until a terminal close succeeds.

Duplicates are preferred over silent loss. Deduplicate by `id` / `re`.
