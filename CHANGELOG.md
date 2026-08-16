# Changelog

All notable changes to Agent Letterbox for cmux are documented here.

## [0.3.2] — 2026-08-16

### Fixed

- **The documented doorbell example did not match what the adapter emits.** README, SPEC and
  the cmux docs showed:

  a short form ending in `check your inbox`, with no type, path or token. The adapter has
  never emitted that shape. It emits:

  ```text
  📬 letterbox doorbell: unacked <type> in <letterbox>/<agent>/inbox/ — please check
  📬 letterbox doorbell: unacked <type> in <letterbox>/<agent>/inbox/ — please check · <8-lowercase-hex>
  ```

  **Impact:** an agent that built its permitted-line rule from the documented example would
  have matched nothing and silently ignored every live doorbell — with no error to diagnose.
  If you configured doorbell acceptance from the docs before 0.3.2, re-check it against the
  two shapes above and match by prefix, never by exact equality.

### Added

- **A docs/code drift gate** (`tests/test_doorbell_docs_drift.sh`, run by `make test`). It
  executes the adapter against a mocked platform CLI, captures the line actually emitted, and
  asserts every documented doorbell line in every tracked file conforms to it. Failures name
  the file and line. A companion mutation harness proves the gate catches planted drift in
  README, SPEC, SKILL and `docs/`, and that it still passes on a clean tree.

  This is the durable fix. The wrong example was a symptom; nothing previously bound the
  documentation to the code.

- **An agent entry point in the README**, naming `skills/agent-letterbox/SKILL.md` as the
  operating manual. The acceptance rule lived only in the skill, and nothing pointed to it.

## [0.3.1] — 2026-08-16

- Correct v0.3 release metadata, roadmap, skill, and specification wording.
- Harden public release gates: tracked-file private-vocabulary scan, hidden/CI residue mutations, and early-abort lifecycle checks.

## [0.3.0] — 2026-08-16

### Added

- v0.3 core: one-shot `reply result` on `requires_ack: false`; path-form `file` of inbound result/nack requires `--read`.
- Safe display-id / unique-token resolution for read, file, reply, progress, and nudge.
- Additive token-bearing doorbell (` · <8hex>`); `nudge` re-rings an open letter; collision lists and refuses.
- Operational `check` (live first, stale last, `--recent` footer, progress age) and read-only `check --thread`.
- Privacy-safe confirmation lines (`display_id`, never basename/slug).

v0.2 letters and token-less doorbells remain valid. Dual-accept doorbell guidance is prefix/pattern only (exact full-line equality is a cutover BLOCK). The `thread` field is still additive/optional; unknown fields stay ignored.

- `tests/test_no_private_vocabulary.sh` is a separate product-cleanliness gate: `make test` fails on private helper/host/transport residue in every tracked file (`git ls-files -z`, including dotted directories such as CI workflows), not a directory allowlist. Hits report file:line. A companion self-mutation harness plants visible, hidden, and workflow residue in a repo copy, runs the real gate, and requires file:line failure; inner output is `[mut]`-prefixed. The harness also asserts the gate PASSes on the cleaned copy, or the plants prove nothing.
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
