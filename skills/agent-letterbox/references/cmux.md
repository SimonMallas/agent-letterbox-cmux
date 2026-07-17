# cmux reference

Use `letterbox cmux run <agent-id> -- <agent-command>` to launch a session in any user-chosen cmux pane or workspace. The wrapper self-registers the current `CMUX_SURFACE_ID`.

For already-running or resumed dynamic/duplicate sessions:

```bash
letterbox cmux register <agent-id>
```

The adapter uses the registered exact surface first, then falls back to configured title patterns. It discovers surfaces across workspaces with `cmux tree --all`.

Automatic input requires `LETTERBOX_CMUX_SUBMIT=1`. It may submit unsent terminal text, so it is intended only for dedicated agent terminals.
