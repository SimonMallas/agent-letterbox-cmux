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

**Not supported (deferred / non-goals):**

Carried forward:

- tmux integration (maintained separately in `agent-letterbox-tmux`).
- Autonomous desktop-agent turns.
- Webhook-triggered unattended processing.
- Persistent watchers, relay/proxy services, or required background daemons.
- Multi-machine transport, databases, dashboards, or MCP dependencies.

New explicit deferrals for v0.2:

- Automatic backlog drain tools that bulk-file inboxes.
- `check --deep` reconciliation of letters that older helpers wrongly archived after ACK.
- A frontmatter protocol-version field (v0.2 keeps the on-disk format unchanged).
- Multi-machine or networked doorbells.
- Built-in chat bridges (external intake remains operator-owned if used at all).
- Session `resume-log` as a public CLI surface.
- A permanent postmaster role or central dispatcher.

## Next milestones

1. Neutralise remaining install/demo roster and hero artwork where needed.
2. Port lifecycle suite CI across macOS and Linux from clean clones.
3. Soak the published artifact (curl + git install paths, one real ack→result cycle).
4. Port the same lifecycle semantics to sibling platform repos one at a time with a real doorbell test each.
