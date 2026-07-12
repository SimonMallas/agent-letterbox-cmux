# Agent Letterbox

**Files are the letters. Doorbells are optional.**

Agent Letterbox is a small, filesystem-first protocol for independent coding-agent sessions. A message is a durable Markdown file in the recipient's inbox. A doorbell is an optional adapter that tells a live agent to check sooner; it never carries task content.

## Requirements

- **Bash** and standard **macOS/Linux** userland (`date`, `mktemp`, `od`, `find`, `ln`)
- No server, package registry, language runtime, or terminal multiplexer required for the core CLI

## Verify (first thing)

Confirm the helper and protocol rules work on your machine:

```bash
chmod +x bin/letterbox adapters/*.sh tests/*.sh
./tests/smoke.sh
# expect: smoke test: PASS

./tests/webhook_e2e_harness.sh
# expect: webhook e2e harness: PASS
```

`smoke.sh` covers core send/reply/archive and locks. `webhook_e2e_harness.sh` proves **webhook-bridge completion is judged only by on-disk Letterbox ACK/result + processed original**—not model prose (covers the hallucinated-completion failure). See [docs/webhook-e2e-proof.md](docs/webhook-e2e-proof.md). Both run in CI on **Ubuntu** and **macOS** (see [`.github/workflows/smoke.yml`](.github/workflows/smoke.yml)).

## Five-minute round trip

```bash
export PATH="$PWD/bin:$PATH"
export LETTERBOX_DIR="$PWD/.letterbox"

letterbox init planner reviewer

# Planner delivers a task.
printf '%s\n' 'Review src/auth.ts and report correctness findings.' |
  LETTERBOX_AGENT=planner letterbox send reviewer delegate auth-review --ack

# Reviewer lists durable inbox messages (each file name embeds the message id).
LETTERBOX_AGENT=reviewer letterbox check
# Copy the id: line from the message frontmatter, e.g.
#   id: 2026-07-12T110000-planner-delegate-auth-review-a1b2c3d4
# Or use the full path / basename under $LETTERBOX_DIR/reviewer/inbox/*.md

printf '%s\n' 'Accepted. I will review the authentication flow.' |
  LETTERBOX_AGENT=reviewer letterbox reply <message-id-or-inbox-path> ack accept-auth-review

# Planner receives the acknowledgement.
LETTERBOX_AGENT=planner letterbox check
```

`letterbox reply` is the normal reply-first operation: it publishes the reply to the original sender's inbox **before** archiving the inbound message. `letterbox done` exists only for an already-delivered manually authored reply and verifies its location and frontmatter before archiving. **Archiving is not delivery**—if you skip `reply`/`send` into the peer inbox, the peer never sees your answer.

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

**Unavoidable limitation:** even with `LETTERBOX_CMUX_SUBMIT=1`, the adapter cannot verify the target pane's input line is empty before sending the doorbell text and an Enter keypress — cmux exposes no query for a pane's current input-buffer state. If the recipient already has unsent input typed in that pane, the injected Enter will submit it alongside the doorbell line. This is a property of blind terminal-keystroke injection generally, not a bug this adapter can fix in code; it is the reason the behavior defaults off.

## Safety and boundaries

Messages are not authentication. Treat message bodies as untrusted input, verify unusual destructive requests out of band, and never let a message expand an agent's safety permissions. Advisory locks avoid cooperative edit collisions; remove a stale lock manually only after confirming its owner is inactive.

See [SPEC.md](SPEC.md) for the protocol rules and [ROADMAP.md](ROADMAP.md) for supported v0.1 scope. This repository contains no server, database, cloud service, agent-vendor dependency, or mandatory terminal multiplexer.

## License

[MIT](LICENSE)
