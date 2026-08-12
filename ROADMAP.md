# Agent Letterbox for cmux roadmap

## v0.2 scope

Agent Letterbox for cmux is a filesystem-first coordination system for live cmux terminal-agent teams.

Public v0.2 is a **correctness** release: task vs non-task lifecycle, non-terminal ACK with `.md.ack` sidecars, terminal NACK/RESULT, `file` for non-task disposal, publish-before-close ordering, and doorbell-after-local-state.

**Supported:**

- Durable Markdown letters in per-agent inboxes.
- Task vs non-task handling (`requires_ack`).
- Non-terminal `ack` (accepted WIP + sidecar); terminal `nack` / `result`.
- `letterbox file` for non-task letters.
- Reply-first publication and recipient-owned archival.
- Atomic message publication, advisory locks, lifecycle locks, and filesystem completion proof.
- Automatic cmux doorbells across panels and workspaces (opt-in submit).
- cmux self-registration for dynamically titled and duplicate agent sessions.
- User-controlled cmux layouts: panels, workspaces, or windows.
- Neutral public examples (`planner`, `reviewer`, `builder`, `researcher`).

**Not supported (deferred / non-goals):**

- Sibling platform products (tmux / Herdr / Zellij — separate repos).
- Autonomous desktop-agent turns.
- Webhook-triggered unattended processing.
- Persistent watchers, relay/proxy services, or required background daemons.
- Multi-machine transport, databases, dashboards, or MCP dependencies.
- Automatic backlog drain tools that bulk-file inboxes.
- `check --deep` reconciliation of letters that older helpers wrongly archived after ACK.
- A frontmatter protocol-version field (v0.2 keeps the on-disk format unchanged).
- Built-in chat bridges (external intake remains operator-owned if used at all).
- Session `resume-log` as a public CLI surface.
- A permanent postmaster role or central dispatcher.

## Next milestones

1. Soak the published v0.2 artifact (curl + git install paths, one real ack→result cycle on live cmux).
2. Keep install/clone/curl URLs single-sourced at canonical `agent-letterbox-cmux`.
3. Keep lifecycle suite CI green on macOS and Linux from clean clones.
4. Port the same lifecycle semantics to sibling platform repos only when each has its own real doorbell proof.
