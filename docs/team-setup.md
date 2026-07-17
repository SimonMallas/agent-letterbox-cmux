# cmux team setup

This is the standard Agent Letterbox setup for a live terminal-agent team.

**You control cmux.** Open whatever panels, workspaces, windows, and agents fit the task. Letterbox never creates or rearranges your cmux layout; it only discovers or registers live agent surfaces and rings them.

## One-time setup

Run once from the Agent Letterbox checkout:

```bash
letterbox cmux setup --agents pi,claude,grok,hermes --submit
```

This creates `~/.agent-letterbox/` by default, including:

```text
inboxes and processed folders for every named agent
cmux-agents.tsv          # live self-registrations
cmux-patterns.tsv        # optional static title patterns
env.sh                   # shared Letterbox/cmux environment
AGENT-LETTERBOX.md       # startup/resume instruction snippet

It also symlinks the bundled `agent-letterbox` skill into `~/.agents/skills/agent-letterbox` (override with `LETTERBOX_SKILLS_DIR`). Agents that support global Agent Skills can then load the same doorbell/reply behavior automatically.
```

`--submit` enables automatic terminal input doorbells. Leave it out if you want visibility notifications only.

Use another shared location when needed:

```bash
letterbox cmux setup --agents planner,reviewer --dir /shared/letterbox --submit
```

## Launch agents in any cmux layout

Open cmux and create your own layout. Then launch each agent inside its chosen pane or workspace through the wrapper:

```bash
letterbox cmux run pi -- pi
letterbox cmux run claude -- claude
letterbox cmux run grok -- grok
letterbox cmux run hermes -- hermes chat
```

The wrapper:

1. loads the generated shared environment;
2. exposes the shared Agent Letterbox skill location;
3. sets `LETTERBOX_AGENT`;
4. self-registers the current live cmux surface;
5. launches the requested agent command.

The agent can live in any workspace. The cmux adapter uses `cmux tree --all` and registered surface IDs to target it across panels and workspaces.

## Dynamic and duplicate agents

The wrapper solves dynamic titles and duplicate runtimes automatically. Give each live session a distinct identity:

```bash
letterbox cmux run pi-research -- pi
letterbox cmux run pi-builder -- pi
letterbox cmux run agent-zero -- agent-zero
```

Each registration maps an identity to its current `surface:N` in the shared `cmux-agents.tsv` registry. Surface IDs change after restart/resume, so use `letterbox cmux run` again whenever the agent is relaunched.

For an already-running agent, register manually from inside its terminal:

```bash
letterbox cmux register claude-review
```

Inspect or remove registrations:

```bash
letterbox cmux status
letterbox cmux unregister claude-review
```

## Send a live handoff

From one agent terminal:

```bash
printf '%s\n' 'Review src/auth.ts and report correctness findings.' |
  letterbox send claude delegate auth-review --ack --now
```

The message is written to Claude's inbox first. If Claude is live, the cmux adapter injects the generic doorbell line into its registered terminal.

For an urgent reply, preserve urgency:

```bash
printf '%s\n' 'ACK: I am reviewing it now.' |
  letterbox reply <message-id> ack auth-review-ack --now
```

## Safety

Automatic terminal input is powerful and intentionally opt-in. `--submit` may submit text already waiting in a target terminal input buffer. Use it only for dedicated agent terminals.

The doorbell contains no task content. The durable letter remains the real message and fallback if an agent is offline.

## Validate

```bash
make test
```

Then send a harmless `--now` delegate between two live agents in separate cmux workspaces. Verify the inbox letter, the target terminal doorbell, the ACK/result, and the archived original.
