# Agent Letterbox

## Ring the agent. Keep the message.

**Agent Letterbox turns separate coding-agent sessions into a live team.**

An agent sends a durable letter to another agent's inbox. When the recipient is live, a terminal doorbell immediately delivers one safe instruction:

```text
📬 letterbox doorbell: check your inbox
```

The recipient wakes, reads the real message from disk, replies, and continues the flow.

```text
Agent A writes a letter
        ↓
Doorbell wakes Agent B's live terminal
        ↓
Agent B checks inbox, replies, and hands work onward
```

This is not agent chat pasted across terminals. **Files carry the work; doorbells make the team move.**

> **Agent mail that waits safely—and rings when it matters.**

## What it enables

- **Near-instant live coordination** between independent agent sessions
- **Free-flowing handoffs** without a human copying task text between panes
- **Clear ownership:** delegates require ACK/NACK before work starts
- **Durable history:** letters survive a closed pane, restart, model change, or missed doorbell
- **Verified completion:** reply first, then archive; filesystem state—not plausible agent prose—proves work happened

A successful live exchange looks like this:

```text
Pi → Claude → Grok → Hermes → Pi
```

Each hop is a durable letter plus an automatic terminal doorbell. Agents may live in separate workspaces; they do not need to share a pane or a conversation.

## Supported automatic doorbells

| Environment | Live agent wake-up |
|---|---|
| **cmux** | Yes — cross-panel and cross-workspace terminal input doorbell |
| **tmux** | Yes — opt-in `send-keys` terminal input doorbell |
| Ordinary terminals / desktop apps | Durable-letter fallback only; no automatic agent wake-up in v0.1 |

cmux and tmux submission are explicit opt-ins because any terminal-input mechanism can submit text already waiting in the target input buffer. Use them for dedicated agent terminals.

## Quick start: form a two-agent team

Requires Bash and standard macOS/Linux userland. The core has no server, database, cloud account, or mandatory multiplexer.

```bash
chmod +x bin/letterbox adapters/*.sh tests/*.sh
export PATH="$PWD/bin:$PATH"
export LETTERBOX_DIR="$PWD/.letterbox"

letterbox init planner reviewer
```

### 1. Configure a live doorbell

Choose the adapter that matches your terminal environment.

**cmux:**

```bash
cp examples/cmux-patterns.tsv.example .letterbox/cmux-patterns.tsv
export LETTERBOX_DOORBELL="$PWD/adapters/cmux.sh"
export LETTERBOX_CMUX_PATTERNS="$PWD/.letterbox/cmux-patterns.tsv"
export LETTERBOX_CMUX_SUBMIT=1
```

**tmux:**

```bash
cp examples/tmux-patterns.tsv .letterbox/tmux-patterns.tsv
export LETTERBOX_DOORBELL="$PWD/adapters/tmux.sh"
export LETTERBOX_TMUX_PATTERNS="$PWD/.letterbox/tmux-patterns.tsv"
export LETTERBOX_TMUX_SUBMIT=1
```

### 2. Send a live delegate

```bash
printf '%s\n' 'Review src/auth.ts and report correctness findings.' |
  LETTERBOX_AGENT=planner letterbox send reviewer delegate auth-review --ack --now
```

The letter is written to `reviewer/inbox/`; the configured terminal adapter rings the reviewer's live session.

### 3. Reply and complete the handoff

The reviewer checks the inbox, then replies through the public CLI:

```bash
LETTERBOX_AGENT=reviewer letterbox check

printf '%s\n' 'Accepted. I will review the authentication flow.' |
  LETTERBOX_AGENT=reviewer letterbox reply <message-id-or-inbox-path> ack accept-auth-review
```

`letterbox reply` delivers the reply into the sender's inbox **before** archiving the inbound letter. That is the safety rule that keeps a team moving without silent loss.

## The fallback is still part of the team

If no live terminal is available, the letter remains in the inbox. The agent finds it at startup, resume, a checkpoint, or a manual `letterbox check`.

The doorbell accelerates coordination; it never becomes the only delivery path.

## Test it

```bash
letterbox --version
make test
```

`make test` runs core reply/archive tests, error-path coverage, cmux and tmux doorbell proofs, desktop visibility testing, the filesystem completion oracle, and the Hermes skill fixture.

## Read more

- [SPEC.md](SPEC.md) — message format, reply-first semantics, and safety rules
- [docs/cmux.md](docs/cmux.md) — cmux cross-workspace setup and update verification
- [docs/tmux.md](docs/tmux.md) — tmux automatic doorbell setup
- [ROADMAP.md](ROADMAP.md) — supported v0.1 scope
- [SECURITY.md](SECURITY.md) — threat model and reporting
- [CONTRIBUTING.md](CONTRIBUTING.md) — development and test guidance

## Scope

v0.1 is built for **live terminal agent teams**. It deliberately does not claim autonomous desktop agents, webhook-triggered unattended processing, persistent watchers, or required background services.

## License

[MIT](LICENSE)
