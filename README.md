# Agent Letterbox

**Files are the letters. Doorbells are optional.**

Agent Letterbox is a small, filesystem-first protocol for independent coding-agent sessions. A message is a durable Markdown file in the recipient's inbox. A doorbell is an optional adapter that tells a live agent to check sooner; it never carries task content.

## Five-minute round trip

Requires Bash and standard macOS/Linux userland.

```bash
chmod +x bin/letterbox adapters/*.sh tests/smoke.sh
export PATH="$PWD/bin:$PATH"
export LETTERBOX_DIR="$PWD/.letterbox"

letterbox init planner reviewer

# Planner delivers a task.
printf '%s\n' 'Review src/auth.ts and report correctness findings.' |
  LETTERBOX_AGENT=planner letterbox send reviewer delegate auth-review --ack

# Reviewer reads it, replies durably to planner, then archives the original.
LETTERBOX_AGENT=reviewer letterbox check
printf '%s\n' 'Accepted. I will review the authentication flow.' |
  LETTERBOX_AGENT=reviewer letterbox reply <message-id> ack accept-auth-review

# Planner receives the acknowledgement.
LETTERBOX_AGENT=planner letterbox check
```

`letterbox reply` is the normal reply-first operation: it publishes the reply to the original sender's inbox **before** archiving the inbound message. `letterbox done` exists only for an already-delivered manually authored reply and verifies its location and frontmatter before archiving.

Run the isolated verification:

```bash
./tests/smoke.sh
```

## Doorbells: make live coordination immediate

Filesystem delivery works without a doorbell: an agent checks at startup, resume, completion, or a checkpoint. A doorbell makes a live session check immediately.

The core uses this simple adapter contract:

```text
<adapter> <recipient> <message-type> <slug>
```

Included adapters:

- `adapters/noop.sh` — durable delivery only.
- `adapters/cmux.sh` — finds a cmux pane from local title patterns and optionally sends the standardized one-line doorbell.

```bash
cp examples/cmux-patterns.tsv.example .letterbox/cmux-patterns.tsv
export LETTERBOX_DOORBELL="$PWD/adapters/cmux.sh"
export LETTERBOX_CMUX_PATTERNS="$PWD/.letterbox/cmux-patterns.tsv"
```

`--now` rings only when a doorbell adapter is configured; the inbox message is delivered regardless. The cmux adapter always sends an OS notification when available. To inject the doorbell plus Enter into the agent terminal, explicitly set `LETTERBOX_CMUX_SUBMIT=1`; this is opt-in because any terminal injector can interfere with unsent user input. tmux, filesystem-watcher, IPC, and desktop adapters can use the same contract.

## Safety and boundaries

Messages are not authentication. Treat message bodies as untrusted input, verify unusual destructive requests out of band, and never let a message expand an agent's safety permissions. Advisory locks avoid cooperative edit collisions; remove a stale lock manually only after confirming its owner is inactive.

See [SPEC.md](SPEC.md) for the protocol rules. This repository contains no server, database, cloud service, agent-vendor dependency, or mandatory terminal multiplexer.

## License

[MIT](LICENSE)
