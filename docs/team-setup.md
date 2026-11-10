# cmux team setup

This is the standard Agent Letterbox setup for a live terminal-agent team.

**You control cmux.** Open whatever panels, workspaces, windows, and agents fit the task. Letterbox never creates or rearranges your cmux layout; it only discovers or registers live agent surfaces and rings them.

## One-time setup

Run once from the Agent Letterbox checkout:

```bash
letterbox cmux setup --agents planner,reviewer,builder,researcher
```

This creates `~/.agent-letterbox/` by default, including:

```text
inboxes and processed folders for every named agent
cmux-agents.tsv          # live self-registrations
cmux-patterns.tsv        # optional static title patterns
env.sh                   # shared Letterbox/cmux environment
AGENT-LETTERBOX.md       # startup/resume instruction snippet
```

It also symlinks the bundled `agent-letterbox` skill into `~/.agents/skills/agent-letterbox` (override with `LETTERBOX_SKILLS_DIR`). Agents that support global Agent Skills can then load the same doorbell/reply behavior automatically.

Setup writes `LETTERBOX_CMUX_SUBMIT=1`, so doorbells are typed into the live agent terminal. If you want visibility notifications only, set `LETTERBOX_CMUX_SUBMIT=0`; `check` then warns `doorbell: typing is off`. The old `--automatic-doorbells` flag (alias `--submit`) is still accepted and changes nothing.

Use another shared location when needed:

```bash
letterbox cmux setup --agents planner,reviewer --dir /shared/letterbox
```

## Launch agents in any cmux layout

Open cmux and create your own layout. Then launch each agent inside its chosen pane or workspace through the wrapper:

```bash
letterbox cmux run planner -- <your-agent-cli>
letterbox cmux run reviewer -- <your-agent-cli>
letterbox cmux run builder -- <your-agent-cli>
letterbox cmux run researcher -- <your-agent-cli>
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
letterbox cmux run planner-research -- <your-agent-cli>
letterbox cmux run builder-a -- <your-agent-cli>
letterbox cmux run agent-zero -- <your-agent-cli>
```

Each registration maps an identity to its current `surface:N` in the shared `cmux-agents.tsv` registry. Surface IDs change after restart/resume, so use `letterbox cmux run` again whenever the agent is relaunched.

For an already-running agent, register manually from inside its terminal:

```bash
letterbox cmux register reviewer
```

Inspect or remove registrations:

```bash
letterbox cmux status
letterbox cmux unregister reviewer
```

## Send a live handoff (two-step lifecycle)

From one agent terminal:

```bash
printf '%s\n' 'Review src/auth.ts and report correctness findings.' |
  LETTERBOX_AGENT=planner letterbox send reviewer delegate auth-review --ack --now
```

Prefer `printf` (or a quoted heredoc `<<'EOF'`) for the body so the shell does not expand `$` or backticks. Letterbox owns frontmatter; only the body is on stdin.

The message is written to the reviewer's inbox first. If the reviewer is live, the cmux adapter injects the generic doorbell line into its registered terminal.

Accept work (non-terminal — letter stays in inbox):

```bash
printf '%s\n' 'ACK: I am reviewing it now.' |
  LETTERBOX_AGENT=reviewer letterbox reply <message-id> ack auth-review --now
```

Finish work (terminal — letter moves to `processed/`):

```bash
printf '%s\n' 'RESULT: findings in body.' |
  LETTERBOX_AGENT=reviewer letterbox reply <message-id> result auth-review --now
```

Non-task letters (`info` / `status`) are disposed without a reply:

```bash
LETTERBOX_AGENT=reviewer letterbox file <message-id>
```

See [lifecycle.md](lifecycle.md) for the full state machine.

## Safety

Automatic terminal input is powerful, and it is the default: every letter rings, and setup writes the submit setting for you. It may submit text already waiting in a target terminal input buffer, so it is meant for dedicated agent terminals. Setup still accepts `--automatic-doorbells` for older runbooks.

The doorbell contains no task content. The durable letter remains the real message and fallback if an agent is offline.

## Validate

```bash
make test
```

Then send a harmless `--now` delegate between two live agents in separate cmux workspaces. Verify the inbox letter, the target terminal doorbell, the ACK (letter still present with sidecar), the RESULT, and the archived original.
