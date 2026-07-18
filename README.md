# Agent Letterbox for cmux

## Ring the bell. Create the team.

![Agent Letterbox for cmux](assets/hero/letterbox-hero-1600x900.png)

**Agent Letterbox for cmux turns separate coding-agent terminals into a live team.**

## What it is

Agent Letterbox is not a model, a new terminal, or a second agent harness. It is the coordination layer that lets the agents you already run hand work to one another without making you the human message relay.

A task is written as a durable letter in the recipient's inbox. When that agent is live, cmux delivers one short, generic instruction into its terminal:

```text
📬 letterbox doorbell: check your inbox
```

The agent wakes, reads the real task from disk, replies, and hands work onward. The terminal gets the knock; the inbox keeps the message.

> **Agent mail that waits safely—and a bell brings it alive.**

## Why it exists

Without coordination, a multi-agent workflow usually means juggling panes, copying task text, remembering who owns what, and hoping an offline agent eventually sees a message.

Directly injecting the full task into another terminal is fast, but the terminal becomes the only message record. Agent Letterbox keeps the fast part—the live doorbell—while putting the actual work in a durable, inspectable letter.

```text
full task → durable inbox letter
live wake-up → short generic doorbell
reply → sender inbox
archive → recipient processed history
```

Read the full comparison in [Why Letterbox?](docs/why-letterbox.md).

## What this opens up

- **Near-instant coordination** — a live agent can receive a doorbell and begin its next turn without human copy/paste.
- **Real handoffs** — implementation, review, research, QA, and fixes can move between agents as explicit owned work.
- **A visible team** — agents can live in separate cmux panels, workspaces, or windows and still coordinate across them.
- **Durable recovery** — if an agent is offline, restarting, busy, or misses the bell, the task remains in its inbox.
- **Clear responsibility** — delegates require ACK/NACK; replies are delivered before originals are archived.
- **Evidence over claims** — inbox, reply, and processed files show what happened even when an agent conversation is gone.
- **Less human relay work** — you direct the team instead of pasting the same request between terminals.

This repository is purpose-built for live cmux agent teams.

---

# Quick start: set up your cmux team

You need macOS or Linux, Bash, Git, and cmux. No server, database, cloud account, or custom cmux layout is required.

## Step 1 — Install Agent Letterbox

Open any terminal window. You can either copy/paste the commands yourself, **or ask an existing coding agent**:

> Set up Agent Letterbox for cmux using the README Quick Start. Do not change my cmux layout.

### Option A — Recommended: copy/paste installer

```bash
curl -fsSL https://raw.githubusercontent.com/SimonMallas/agent-letterbox-cmux/main/install.sh | sh
export PATH="$HOME/.local/bin:$PATH"
letterbox cmux setup --agents pi,claude,grok,hermes --automatic-doorbells
source "$HOME/.agent-letterbox/env.sh"
```

This downloads a local copy and sets up the team. If you are new to GitHub, you do not need to understand Git first—copying the block is enough.

To update later, run the same installer again:

```bash
curl -fsSL https://raw.githubusercontent.com/SimonMallas/agent-letterbox-cmux/main/install.sh | sh
```

### Option B — Manual Git install

Use this if you want to inspect the source, modify it, or contribute:

```bash
git clone https://github.com/SimonMallas/agent-letterbox-cmux.git \
  ~/Developer/agent-letterbox-cmux
cd ~/Developer/agent-letterbox-cmux
chmod +x bin/letterbox adapters/*.sh tests/*.sh
export PATH="$PWD/bin:$PATH"
letterbox cmux setup --agents pi,claude,grok,hermes --automatic-doorbells
source "$HOME/.agent-letterbox/env.sh"
```

Both options automatically create one shared Letterbox, agent inboxes, the global `letterbox` launcher, the shared Agent Letterbox skill, and the live-surface registration registry.

> `--automatic-doorbells` lets Letterbox type the generic doorbell into a live agent terminal. Use it only for dedicated agent terminals: like any terminal-input tool, it can submit text already typed in a target terminal.

## Step 2 — Open cmux your way

Open cmux and arrange agents however the task requires:

```text
one workspace per agent
four-panel grid
separate windows
any mix that suits the task
```

Agent Letterbox does not create, move, or resize your panels.

## Step 3 — Launch agents through Letterbox

In each agent's chosen cmux pane, use the launcher:

```bash
letterbox cmux run pi -- pi
letterbox cmux run claude -- claude
letterbox cmux run grok -- grok
letterbox cmux run hermes -- hermes
```

The launcher gives the agent an identity, registers its current cmux surface, and starts it. That is what lets Letterbox find and ring agents across workspaces.

## Step 4 — Send the first handoff

From the Pi terminal:

```bash
printf '%s\n' 'Review src/auth.ts and report correctness findings.' |
  LETTERBOX_AGENT=pi letterbox send claude delegate auth-review --ack --now
```

Claude receives a durable letter and a live cmux doorbell. To reply:

```bash
printf '%s\n' 'ACK: I will review it now.' |
  letterbox reply <message-id-or-inbox-path> ack auth-review-ack --now
```

## New or duplicate agents

Give each new or duplicate session a unique identity:

```bash
letterbox cmux run pi-research -- pi
letterbox cmux run pi-builder -- pi
letterbox cmux run agent-zero -- agent-zero
```

Each self-registers its exact current cmux surface, avoiding title collisions.

## Test the installation

```bash
letterbox --version
make test
```

## Learn more

- [docs/why-letterbox.md](docs/why-letterbox.md) — why durable letters plus generic doorbells beat direct task injection
- [docs/team-setup.md](docs/team-setup.md) — detailed cmux team setup
- [docs/cmux.md](docs/cmux.md) — cross-workspace operation and update verification
- [SPEC.md](SPEC.md) — message format and reply-first semantics
- [SECURITY.md](SECURITY.md) — threat model and reporting

## License

[MIT](LICENSE)
