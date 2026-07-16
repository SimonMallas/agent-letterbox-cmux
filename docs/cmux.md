# cmux adapter guide

The Agent Letterbox cmux adapter is optional. The durable letter is always written first; cmux only delivers the generic prompt that tells a live terminal agent to inspect its inbox.

## Workspace model

Agent Letterbox works across cmux workspaces. The adapter discovers terminal surfaces with:

```bash
cmux tree --all
```

It then targets the discovered surface explicitly. Agents do not need to share a workspace to exchange letters or doorbells.

For a multi-agent setup, use one workspace per live terminal agent and save that arrangement as a **cmux saved workspace layout**. Newer cmux releases can reopen a named layout and set one as the default for new workspaces.

## Configure title patterns

Create a local, tab-separated pattern file:

```text
# agent<TAB>stable terminal-title substring
planner	planner
reviewer	reviewer
```

Then configure the adapter:

```bash
export LETTERBOX_DOORBELL="$PWD/adapters/cmux.sh"
export LETTERBOX_CMUX_PATTERNS="$PWD/.letterbox/cmux-patterns.tsv"
```

Use one row per known title marker. Patterns are local configuration, not protocol data.

## Safety: terminal input is opt-in

By default, the adapter sends a cmux/macOS notification only. To inject the standardized doorbell line and Enter into the target terminal, explicitly opt in:

```bash
export LETTERBOX_CMUX_SUBMIT=1
```

This can submit unsent text already present in the target terminal input buffer. Use it only for dedicated agent terminals where that risk is acceptable.

## cmux update procedure

Do not update cmux while important agents are running. First let current turns settle or record their state.

After an update:

```bash
cmux version
cmux tree --all
```

Then run a harmless cross-workspace Letterbox smoke check:

1. Send a `priority: now` `info` letter to a live agent in another workspace.
2. Confirm the letter appears in that agent's inbox.
3. Confirm the standardized doorbell reaches the intended surface.
4. Confirm no other surface received injected input.

If a pane looks stale after sleep/wake, use cmux diagnostics before reusing old surface references:

```bash
cmux surface-health
cmux refresh-surfaces
cmux tree --all
```

Always rediscover current surfaces; never retain an old `surface:N` reference across a restart, sleep/wake, or update.

## Hooks

cmux includes agent hook integrations for some runtimes. Review and configure these through cmux's own hook setup flow after an update; Agent Letterbox does not install or modify hooks automatically.
