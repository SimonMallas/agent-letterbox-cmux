# Why Agent Letterbox instead of direct terminal messages?

Direct terminal injection is useful. A tool can type a task into another live agent terminal, press Enter, and the agent starts work immediately.

Agent Letterbox deliberately uses a different split:

```text
Durable task content → letter on disk
Live wake-up         → short generic doorbell in the terminal
```

## The direct-injection model

```text
send full task text into Agent B's terminal
→ press Enter
→ Agent B starts immediately
```

This is fast, but the terminal becomes both the message transport and the work record.

## The Letterbox model

```text
write full task to Agent B's inbox
→ inject: “📬 letterbox doorbell: unacked <type> in <letterbox>/<agent>/inbox/ — please check”
→ Agent B reads the durable letter
→ Agent B ACKs (work stays visible), then RESULTs (archives)
```

The doorbell is still an automatic live-agent wake-up. It is not a human notification or a manual relay. It is best-effort; the letter is the record.

## Why separate the letter from the bell?

| Direct task injection | Letterbox + generic doorbell |
|---|---|
| Fastest local handoff | Near-instant live handoff |
| Task text lives in terminal history | Task is a durable Markdown file |
| Weak recovery if a terminal is offline or state is wrong | Letter waits safely for startup/resume/checkpoint |
| Long text may be duplicated on retry | Retry only rings the bell; letter remains one source of truth |
| Harder to inspect/audit task ownership | Inbox, ACK sidecar, result, and processed archive provide an audit trail |
| Arbitrary task content is injected into a live composer | Only a fixed generic line is injected |

Terminal scrollback is a weaker boundary than the filesystem, so the task never goes through the doorbell line.

## The practical result

Agent Letterbox keeps the useful part of direct injection:

```text
wake the live agent now
```

while making the actual task durable:

```text
keep the message safe, inspectable, and recoverable
```

Letterbox is that thin shared layer — correspondence, handoffs, decisions,
ACKs/RESULTs, recoverable history. It is not a memory intelligence system:
no summarization, embeddings, ranking, promotion, or interpretation. A
separate layer may use the records.

> **Ring the bell. Keep the message.**

If an agent is offline, the letter is not lost. If the bell arrives, the agent can respond immediately. That is the point of the system.
