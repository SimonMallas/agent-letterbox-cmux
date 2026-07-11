# Agent Bus Protocol

A small, filesystem-first coordination protocol for independent coding-agent sessions.

**Files are the letters. Notifications are only doorbells. Terminal panes are never the envelope.**

Agent Bus Protocol (ABP) gives agents durable inboxes, explicit delegation acknowledgement, reply-first archival, and advisory resource leases—without a server, database, MCP dependency, or required terminal multiplexer.

## Why

Putting substantive instructions directly into another agent's terminal is fragile: it interrupts work, loses history, and fails when the session is offline. ABP writes a human-readable Markdown message into the recipient's inbox instead. The recipient handles it at a session boundary or after an optional doorbell wakes a live session.

## Quick start

```bash
# Clone this repository, then make the helper executable.
chmod +x bin/agent-bus adapters/*.sh
export PATH="$PWD/bin:$PATH"
export AGENT_BUS_DIR="$PWD/.agent-bus"

agent-bus init planner reviewer

# Planner sends a delegate. The message body comes from stdin.
printf '%s\n' 'GOAL: Review src/auth.ts.\nDONE-WHEN: Report correctness findings.' |
  AGENT_BUS_AGENT=planner agent-bus send reviewer delegate auth-review --ack

# Reviewer reads its durable inbox.
AGENT_BUS_AGENT=reviewer agent-bus check
```

To reply, write a normal ABP message into the sender's inbox with `re:` equal to the original message ID, then archive the original safely:

```bash
AGENT_BUS_AGENT=reviewer agent-bus done <message-id> --reply ./reply.md
```

See [SPEC.md](SPEC.md) for the message format and recovery rules.

## Optional cmux doorbells

The protocol does **not** require cmux. With no doorbell, messages wait safely for the recipient's next startup, completion boundary, or explicit inbox check.

For an immediate local wake-up in a live cmux terminal, configure the adapter:

```bash
cp examples/cmux-patterns.tsv.example .agent-bus/cmux-patterns.tsv
export AGENT_BUS_DOORBELL="$PWD/adapters/cmux.sh"
export AGENT_BUS_CMUX_PATTERNS="$PWD/.agent-bus/cmux-patterns.tsv"

printf '%s\n' 'Please inspect the failing test.' |
  AGENT_BUS_AGENT=planner agent-bus send reviewer request inspect-test --now --ack
```

The patterns file maps an agent to one or more title substrings. It is deliberately local configuration: title formats differ between tools, themes, and machines. The adapter fails open—if it cannot find a live pane, the already-written inbox message remains available.

## Included

- `bin/agent-bus` — Bash helper: initialize, send, check, archive, status, and lock.
- `SPEC.md` — the portable protocol rules.
- `adapters/noop.sh` — explicit no-doorbell behavior.
- `adapters/cmux.sh` — optional local cmux doorbell adapter.
- `tests/smoke.sh` — isolated smoke test.

## Design boundaries

This project intentionally does not include a central server, background daemon, agent-specific title assumptions, external chat service, or credentials. Add an adapter only when your environment needs one.

## License

[MIT](LICENSE)
