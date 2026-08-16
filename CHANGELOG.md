# Changelog

All notable changes to Agent Letterbox for cmux are documented here.

## Unreleased

### Added

- v0.3 core: one-shot `reply result` on `requires_ack: false`; path-form `file` of inbound result/nack requires `--read`.
- Safe display-id / unique-token resolution for read, file, reply, progress, and nudge.
- Additive token-bearing doorbell (` · <8hex>`); `nudge` re-rings an open letter; collision lists and refuses.
- Operational `check` (live first, stale last, `--recent` footer, progress age) and read-only `check --thread`.
- Privacy-safe confirmation lines (`display_id`, never basename/slug).

v0.2 letters and token-less doorbells remain valid. Dual-accept doorbell guidance is prefix/pattern only (exact full-line equality is a cutover BLOCK). The `thread` field is still additive/optional; unknown fields stay ignored.

`VERSION` remains 0.2.0 until release integration.

- `tests/test_no_private_vocabulary.sh` is a separate product-cleanliness gate: `make test` fails on private helper/host/transport residue in the public sweep set.
- Lifecycle v0.2 and v0.3 register an EXIT-trap plus expected-count and a final `PASS` footer so an early abort cannot green-wash. `make test` requires those footers. Mutation coverage proves `exit 0` and a set -e abort after the first assertion fail with an explicit incomplete-footer error.
- Adapter compatibility: the v0.2 doorbell line is a byte-prefix of the v0.3 line, asserted through `adapters/cmux.sh` (not only the helper formatter).

## [0.2.0] — 2026-08-11

Public v0.2 establishes a durable task lifecycle and documents the resulting state machine.

### Fixed

- `reply <id> ack` marks a task as accepted work in progress and leaves it in the inbox; only `nack` and `result` close it.
- The doorbell now rings after the letter's local state has settled, not before.
- `check` excludes `.ack` sidecars from the letter count and warns about an orphan sidecar.
- Message parsing tolerates CRLF line endings.
- A failed reply link is recovered deterministically rather than aborting.

### Added

- `.md.ack` sidecar marking a letter as accepted and in progress.
- `letterbox file <id>` to dispose of a letter that requires no acknowledgement.
- Lifecycle locking so concurrent replies to the same letter converge on one terminal state.
- Derived `thread` field on ownership replies.
- `docs/lifecycle.md` and expanded SPEC/README lifecycle wording.
- cmux-specific product extraction, public curl installer, and copy/paste installation path (folded from earlier unreleased main history).

### Changed

- `SPEC.md` raised to v0.2 with an explicit letter state machine and task vs non-task rules.
- `done` refuses to close a letter that has been acknowledged; use `reply <id> result|nack`.
- `file` refuses letters that require acknowledgement.
- `send` rejects freeform `ack`, `nack`, and `result`; use `reply` for ownership responses so the helper derives their link and retry identity.
- `delegate` now requires `--ack`.
- Documentation examples use neutral role identities (`planner`, `builder`, `reviewer`, `researcher`).

### Compatibility

- Additive message-format change: ownership replies carry an optional `thread` field. Existing letters remain valid; older readers ignore unknown frontmatter keys.
- Existing scripts that send freeform `ack`, `nack`, or `result` must switch to `letterbox reply <id> <ack|nack|result> <slug>`.
- Existing delegate sends must include `--ack`.
- All agents in a team must run the same v0.2 helper version.
- Pre-release checkouts should be reinstalled from the current branch; see "Using a pre-release checkout" in the README.

## [0.1.0] — 2026-07-16

### Added

- Durable Letterbox CLI with atomic publish, reply-first handling, locks, and completion checks.
- Opt-in automatic cmux terminal doorbells across panels and workspaces.
- cmux self-registration for dynamically titled and duplicate agent sessions.
- One-command cmux team setup and agent launcher.
- Core, error-path, cmux adapter, registration, and bootstrap tests.
- README, setup, security, and contribution documentation.
