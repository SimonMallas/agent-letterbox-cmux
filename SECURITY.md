# Security Policy

## Supported versions

Until a public tag is cut, treat **main / pre-release** as the only line that receives security fixes. Once `v0.1.x` is tagged, report issues against the latest patch of that minor line.

## What this project is (and is not)

Agent Letterbox is a **local filesystem protocol** plus a small Bash CLI. It has:

- No network server in the core path
- No authentication of message authors
- No encryption of letters on disk
- No multi-tenant isolation beyond OS file permissions

**Anyone (or any process) who can write to a peer’s inbox directory can plant a letter.** Treat inbox contents as **untrusted data**, not as authority.

## Threat model (v0.1)

| Trust | Assumption |
|-------|------------|
| Disk layout | You choose `LETTERBOX_DIR` on a machine and filesystem you control |
| Agents | Cooperative agents follow reply-first and do not expand permissions from letter bodies |
| Doorbells | Optional adapters only signal a live session; they must not carry task content |
| Locks | Advisory only — not a security boundary |

### Expected operator practices

1. **Permissions:** Restrict `LETTERBOX_DIR` to users/processes that should coordinate (e.g. `0700` / group-only as appropriate).
2. **Untrusted bodies:** Verify unusual, destructive, or identity-sensitive requests out of band before acting.
3. **No permission expansion:** A letter must never grant an agent tools, paths, or network rights it did not already have.
4. **Doorbell injection:** Opt-in terminal submit modes (e.g. `LETTERBOX_CMUX_SUBMIT=1`) can inject keystrokes into a live pane; leave them off unless you accept that risk.
5. **Optional adapters:** Desktop notification/activation and webhook experiments are **not** a secure remote control channel. Do not expose doorbell or webhook surfaces to untrusted networks for v0.1.

### Explicitly out of scope for v0.1 core

- Cryptographic signing of letters
- Mutual authentication of agents
- Remote multi-machine transport
- Autonomous unattended processing triggered by desktop or webhook without a human-in-the-loop terminal agent

See [ROADMAP.md](ROADMAP.md).

## Reporting a vulnerability

Please **do not** open a public issue for security-sensitive reports.

1. Contact the maintainer privately (repository owner on GitHub, or the contact listed on the public project page once published).
2. Include: affected version/commit, reproduction steps, impact, and any suggested fix.
3. Allow a reasonable window for a patch before public disclosure.

If the project is still private, use the same private channel you already use with the maintainer.

## Safe defaults for integrators

- Prefer **session-boundary / terminal-first** checking over unattended bridges.
- Judge completion by **on-disk** reply + archive (filesystem oracle), never by model prose alone.
- Do not ship configs that bind experimental HTTP doorbells to non-loopback interfaces without authentication and a separate threat review.
