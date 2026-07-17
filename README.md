# Agent Letterbox for cmux

## Ring the bell. Create the team.

![Agent Letterbox for cmux](assets/hero/letterbox-hero-1600x900.png)

**Agent Letterbox for cmux turns separate coding-agent terminals into a live team.**

A message is saved safely on disk. When the recipient is live, cmux delivers one short instruction into its terminal:

```text
📬 letterbox doorbell: check your inbox
```

The agent checks the durable message, replies, and hands work onward.

> **Agent mail that waits safely—and a bell brings it alive.**

## What this opens up

- Near-instant coordination between live agents
- Agent-to-agent handoffs without a human copying task text between terminals
- Durable messages that survive restarts, model changes, and missed doorbells
- Clear ownership through ACK/NACK and reply-first handling
- A team that can work across separate cmux workspaces

The automatic doorbell in this repository is **cmux only**. Ordinary terminals and desktop apps still receive durable mail, but need a manual/session-start check.

---

# Quick start: set up your cmux team

You need macOS or Linux, Bash, Git, and cmux. No server, database, cloud account, or custom cmux layout is required.

## Step 1 — Open a terminal and copy/paste this

Open any terminal window. You can either copy/paste the whole block below yourself, **or ask an existing coding agent**:

> Set up Agent Letterbox for cmux using the README Quick Start. Do not change my cmux layout.

```bash
git clone https://github.com/SimonMallas/agent-letterbox-cmux.git \
  ~/Developer/agent-letterbox-cmux
cd ~/Developer/agent-letterbox-cmux
chmod +x bin/letterbox adapters/*.sh tests/*.sh
export PATH="$PWD/bin:$PATH"
letterbox cmux setup --agents pi,claude,grok,hermes --automatic-doorbells
source "$HOME/.agent-letterbox/env.sh"
```

This downloads a local copy and sets up the team. If you are new to GitHub, you do not need to understand Git first—copying the block is enough.

If it is already downloaded:

```bash
cd ~/Developer/agent-letterbox-cmux
git pull
export PATH="$PWD/bin:$PATH"
letterbox cmux setup --agents pi,claude,grok,hermes --automatic-doorbells
source "$HOME/.agent-letterbox/env.sh"
```

Setup automatically creates one shared Letterbox, agent inboxes, the global `letterbox` launcher, the shared Agent Letterbox skill, and the live-surface registration registry.

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

- [docs/team-setup.md](docs/team-setup.md) — detailed cmux team setup
- [docs/cmux.md](docs/cmux.md) — cross-workspace operation and update verification
- [SPEC.md](SPEC.md) — message format and reply-first semantics
- [SECURITY.md](SECURITY.md) — threat model and reporting

## License

[MIT](LICENSE)
