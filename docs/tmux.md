# tmux adapter guide

Agent Letterbox supports automatic live-agent doorbells in tmux through the same durable-letter-first pattern used by the cmux adapter.

```text
letter written to inbox
→ tmux adapter sends the generic doorbell text into a live tmux session
→ agent checks its durable inbox
```

## Configure a session pattern

Create a local tab-separated pattern file:

```text
# agent<TAB>tmux-session-name
receiver	my-agent-session
```

Configure the adapter:

```bash
export LETTERBOX_DOORBELL="$PWD/adapters/tmux.sh"
export LETTERBOX_TMUX_PATTERNS="$PWD/.letterbox/tmux-patterns.tsv"
```

The configured session must be live. The adapter checks it with `tmux has-session`.

## Enable automatic agent input

By default, the adapter sends a tmux visibility message only. To inject the standardized doorbell line and Enter into the live agent terminal, explicitly opt in:

```bash
export LETTERBOX_TMUX_SUBMIT=1
```

This uses:

```bash
tmux send-keys -t <session> -l '<doorbell>'
tmux send-keys -t <session> Enter
```

## Safety

`LETTERBOX_TMUX_SUBMIT=1` can submit text already waiting in the target terminal input buffer. Use it only for dedicated agent sessions where that risk is acceptable.

The doorbell contains no task content. The agent must already be instructed to check its Letterbox inbox and use the reply-first workflow.

## Validate

Run the live disposable test:

```bash
./tests/test_tmux_doorbell.sh
```

It starts a temporary tmux session, injects the real standardized doorbell, captures the target pane, and verifies receipt. The main `make test` suite includes this test.
