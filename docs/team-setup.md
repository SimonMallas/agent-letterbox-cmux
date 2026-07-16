# cmux team setup

This is the standard Agent Letterbox setup for a live terminal-agent team. You choose the cmux layout: one workspace per agent, a multi-panel workspace, separate windows, or a mix. Agent Letterbox does not create or own panels.

## 1. Choose one shared Letterbox directory

Every participating agent must use the same directory:

```bash
export LETTERBOX_DIR="$HOME/.agent-letterbox"
```

Initialize the identities you plan to use:

```bash
letterbox init pi claude grok hermes
```

Each identity gets an `inbox/` and `processed/` directory under the shared Letterbox.

## 2. Configure automatic cmux doorbells

```bash
export LETTERBOX_DOORBELL="$PWD/adapters/cmux.sh"
export LETTERBOX_CMUX_PATTERNS="$LETTERBOX_DIR/cmux-patterns.tsv"
export LETTERBOX_CMUX_SUBMIT=1
```

`LETTERBOX_CMUX_SUBMIT=1` is required for automatic agent input. It can submit text already present in a target terminal input buffer, so use it only for dedicated agent terminals.

## 3. Register agents by the right method

### Stable, unique terminal titles

A stable title pattern is sufficient for one instance of an agent:

```text
# $LETTERBOX_DIR/cmux-patterns.tsv
pi	π -
hermes	hermes
grok	grok
```

The adapter discovers these agents anywhere in cmux with `cmux tree --all`, including other workspaces.

### Dynamic or duplicate agent terminals

Do not use a shared title pattern for dynamically titled agents or two sessions of the same runtime. Give every live session a distinct Letterbox identity and self-register it from inside that terminal:

```bash
letterbox cmux register claude-review
letterbox cmux register pi-research
letterbox cmux register pi-builder
```

Registration records the current `CMUX_SURFACE_ID` in:

```text
$LETTERBOX_DIR/cmux-agents.tsv
```

The cmux adapter prefers this exact surface mapping over title patterns.

## 4. Add startup/resume instructions to every agent

Each participating agent should be told:

```text
At startup or resume:
1. If your title is dynamic or you share a runtime with another session, run:
   letterbox cmux register <your-identity>
2. Run: letterbox check
3. For actionable letters, reply first with letterbox reply, then verify inbox state.
4. Preserve priority: use --now on a reply only when the original letter had priority: now.
```

Surface IDs are temporary, so dynamic/duplicate sessions must re-register after a restart or resume.

## 5. Validate the team

Send a harmless urgent letter to a live agent in another workspace:

```bash
printf '%s\n' 'Doorbell smoke test. Reply with an ACK only.' |
  LETTERBOX_AGENT=pi letterbox send hermes delegate doorbell-smoke --ack --now
```

Verify all of the following:

1. The recipient letter appears in the correct inbox.
2. The standard doorbell reaches the intended cmux surface.
3. The recipient sends an ACK/result.
4. The reply is in the sender inbox and the original is in recipient `processed/`.

## Layout is your choice

Agent Letterbox works with:

```text
one agent per workspace
multiple agents in one workspace
multiple cmux windows
mixed layouts
```

The only requirement for automatic cmux doorbells is a live, discoverable or self-registered terminal surface.
