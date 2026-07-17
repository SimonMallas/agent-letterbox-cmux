# Agent Letterbox for cmux roadmap

## v0.1 scope

Agent Letterbox for cmux is a filesystem-first coordination system for live cmux terminal-agent teams.

**Supported:**

- Durable Markdown letters in per-agent inboxes.
- Reply-first handling and recipient-owned archival.
- Atomic message publication, advisory locks, and filesystem completion proof.
- Automatic cmux doorbells across panels and workspaces.
- cmux self-registration for dynamically titled and duplicate agent sessions.
- User-controlled cmux layouts: panels, workspaces, or windows.

**Not supported:**

- tmux integration (maintained separately in `agent-letterbox-tmux`).
- Autonomous desktop-agent turns.
- Webhook-triggered unattended processing.
- Persistent watchers, relay/proxy services, or required background daemons.
- Multi-machine transport, databases, dashboards, or MCP dependencies.

## Next milestones

1. Review/import approved visual identity assets and social card.
2. Dogfood cmux team setup with real agents after major cmux updates.
3. Release public v0.1 after final private presentation review.
