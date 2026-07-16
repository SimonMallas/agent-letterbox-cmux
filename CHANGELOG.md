# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html)
for **tagged releases**. Until the first public tag, treat versions as pre-release.

## [Unreleased]

### Added

- cmux adapter guide covering saved workspace layouts, cross-workspace discovery, update safety, and post-update doorbell verification.
- Opt-in tmux `send-keys` automatic agent doorbell plus a live disposable tmux proof and setup guide.
- Reframed the README around live, near-instant cross-agent coordination through cmux/tmux doorbells.

## [0.1.0] — 2026-07-16

### Added

- Release readiness docs: `SECURITY.md`, `CONTRIBUTING.md`, this `CHANGELOG.md`.
- `ROADMAP.md` — explicit **terminal-first v0.1** scope; autonomous desktop/webhook processing deferred.
- Core CLI `bin/letterbox` with init, send, check, reply, done, status, advisory locks.
- Optional doorbell adapters: `noop`, `cmux` (opt-in submit), `tmux`, macOS `desktop` (notify/activate only).
- Filesystem e2e oracle + harness (`tests/webhook_e2e_*`) proving completion by on-disk ACK/result + processed original, not model prose.
- CI smoke workflow (Ubuntu + macOS) for core and adapter safety tests.
- Portable Hermes skill packaging under `integrations/hermes/` (research/integration aid; not unattended automation).

### Changed

- Rebranded from early Agent Bus Protocol reference naming to **Agent Letterbox**.
- Reply path hardened: `letterbox reply` publishes then archives; undelivered `done` is rejected.
- Urgent reply doorbells preserved when original priority is `now`.
- cmux adapter: terminal keystroke submit gated behind `LETTERBOX_CMUX_SUBMIT=1` with documented blind-input limitation.
- Advisory lock names now distinguish path separators from literal hyphens.
- Added full `make test` gate, real error-path coverage, and CLI `--version` support.

### Security

- Documented untrusted-letter model, advisory locks, and doorbell injection risks in `SECURITY.md`.

[Unreleased]: https://github.com/SimonMallas/agent-letterbox/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/SimonMallas/agent-letterbox/releases/tag/v0.1.0
