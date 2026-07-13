# Agent Letterbox Roadmap

## v0.1 scope

Agent Letterbox is a filesystem-first coordination protocol for coding agents.

**Supported in v0.1:**

- Durable Markdown letters in per-agent inboxes.
- Reply-first handling and recipient-owned archival.
- Atomic message publication, advisory locks, and filesystem completion proof.
- Immediate doorbells for live terminal agents through optional cmux adapters.
- tmux and desktop adapters as notification/visibility adapters where their platform capabilities permit.
- No-op/session-boundary inbox checking when no doorbell exists.

**Not supported in v0.1:**

- Autonomous desktop-agent turns.
- Webhook-triggered unattended Letterbox processing.
- Persistent inbox watchers, retry supervisors, or cmux relay/proxy services.
- Multi-machine transport, databases, dashboards, MCP servers, or required daemons.

Desktop activation/notification is a human-visible hint only. It must not be presented as proof that an agent started a turn or checked its inbox.

## Next milestones

1. Document and test the terminal cmux/tmux path thoroughly.
2. Expand core error-path, lock, reply, and adapter tests.
3. ~~Add release/security/contribution documentation.~~ **Done** (`SECURITY.md`, `CONTRIBUTING.md`, `CHANGELOG.md`).
4. Dogfood the private repository with terminal-agent round trips.
5. Release public `v0.1.0` only after private dogfooding is stable.

v0.1 remains **terminal-first**: optional doorbells wake live sessions; they do not replace human- or session-driven inbox handling.

## Deferred integrations

Hermes webhook and desktop research established that they can trigger visibility or a fresh turn, but have not demonstrated reliable unattended Letterbox handling. Keep the Hermes skill and filesystem oracle as research/proof artifacts; do not enable a webhook bridge or watcher without a new end-to-end proof.
