# tmux reference

The tmux adapter uses configured live session names and, with `LETTERBOX_TMUX_SUBMIT=1`, sends the standardized doorbell through `tmux send-keys` plus Enter.

It has the same dedicated-terminal safety requirement as cmux: input injection can submit text already present in the target terminal buffer.
