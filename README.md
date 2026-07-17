# Agent Letterbox

## Ring the agent. Keep the message.

**Agent Letterbox turns separate coding-agent terminals into a live team.**

A message is saved safely on disk. When the recipient is live, a doorbell sends one short instruction into its terminal:

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
- A practical way to turn individual agent terminals into one coordinated team

The supported automatic doorbell platforms are **cmux** and **tmux**. Ordinary terminals and desktop apps still receive durable mail, but need a manual/session-start check in v0.1.

---

# Quick start: set up your cmux team

You need macOS or Linux, Bash, Git, and cmux. No server, database, cloud account, or custom cmux layout is required.

## Step 1 — Open a terminal and copy/paste this

Open any terminal window. Copy and paste this whole block into it:

```bash
git clone https://github.com/SimonMallas/agent-letterbox.git \
  ~/Developer/agent-letterbox
cd ~/Developer/agent-letterbox
chmod +x bin/letterbox adapters/*.sh tests/*.sh
export PATH="$PWD/bin:$PATH"
letterbox cmux setup --agents pi,claude,grok,hermes --automatic-doorbells
```

This downloads a local copy of Agent Letterbox, then sets up the team. Because the repository is private today, your GitHub account needs access to it first.

If you already downloaded it, copy/paste this instead:

```bash
cd ~/Developer/agent-letterbox
git pull
export PATH="$PWD/bin:$PATH"
letterbox cmux setup --agents pi,claude,grok,hermes --automatic-doorbells
```

You can also ask an existing coding agent:

> Install Agent Letterbox using the README Quick Start. Do not change my cmux layout.

This automatically:

- creates one shared Letterbox at `~/.agent-letterbox`
- creates inboxes for Pi, Claude, Grok, and Hermes
- installs the `letterbox` command into `~/.local/bin`
- installs the shared `agent-letterbox` skill into `~/.agents/skills`
- creates the live-surface registration registry
- enables automatic cmux doorbells

> `--automatic-doorbells` means Letterbox may type the safe generic doorbell line into a live agent terminal. This is what makes the team respond immediately. Use it only for dedicated agent terminals: like any terminal-input tool, it can submit text already typed in a target terminal.

Stay in this same terminal for the next step; you do not need to open another one yet.

## Step 2 — Open cmux your way

Open cmux and arrange agents however you prefer:

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

Copy and paste the appropriate command into each agent's chosen cmux pane or workspace. The launcher gives the agent its identity, registers its current cmux surface, and starts the command. This is what lets Letterbox find and ring agents across workspaces.

## Step 4 — Send the first handoff

From the Pi terminal:

```bash
printf '%s\n' 'Review src/auth.ts and report correctness findings.' |
  LETTERBOX_AGENT=pi letterbox send claude delegate auth-review --ack --now
```

Claude receives a durable letter in its inbox and a live cmux doorbell. Claude then runs:

```bash
letterbox check
```

To reply:

```bash
printf '%s\n' 'ACK: I will review it now.' |
  letterbox reply <message-id-or-inbox-path> ack auth-review-ack --now
```

The reply reaches Pi before Claude's original letter is archived.

---

## New or duplicate agents

For a new agent, or multiple sessions of the same runtime, give each session its own identity:

```bash
letterbox cmux run pi-research -- pi
letterbox cmux run pi-builder -- pi
letterbox cmux run agent-zero -- agent-zero
```

Each live session self-registers its exact current cmux surface. This avoids title collisions when two Pi, Claude, Hermes, Grok, or other agent sessions are open.

## Test the installation

```bash
letterbox --version
make test
```

`make test` runs core delivery/reply tests, error paths, cmux/tmux doorbell proofs, and completion-oracle checks.

## Learn more

- [docs/team-setup.md](docs/team-setup.md) — detailed cmux team setup
- [docs/cmux.md](docs/cmux.md) — cmux cross-workspace operation and update verification
- [docs/tmux.md](docs/tmux.md) — tmux automatic doorbell setup
- [SPEC.md](SPEC.md) — message format and reply-first semantics
- [ROADMAP.md](ROADMAP.md) — v0.1 scope
- [SECURITY.md](SECURITY.md) — threat model and reporting
- [CONTRIBUTING.md](CONTRIBUTING.md) — development guidance

## Scope

v0.1 is for live terminal-agent teams. It does not claim autonomous desktop agents, webhook-triggered unattended processing, persistent watchers, or required background services.

## License

[MIT](LICENSE)
