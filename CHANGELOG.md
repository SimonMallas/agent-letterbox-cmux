## [0.7.1] — unreleased (cmux edition)

- `check` ignores a `LETTERBOX_CHECK_STALE_DAYS` that is not a whole number (such as `08`, `1.5` or a word) instead of aborting, and a broken link that sorts first in the inbox no longer hides every letter after it.
- A progress note from another agent is shown without terminal control characters.
- `letterbox token` no longer prints nothing when any mailbox holds one malformed file.
- `cmux register` refuses a surface whose ref is only a prefix of a live one. `cmux setup` keeps the registrations when the cmux lookup fails, and stores `--dir` as an absolute path, ignoring `CDPATH`.
- Every ring now uses the box's generated `env.sh` when the caller has no doorbell set, so `send`, `reply` and `nudge` from an agent that was not started by `letterbox cmux run` ring too. Before, they reported `adapter_unavailable` and rang nobody. An explicit doorbell setting still takes precedence. Your own `check` prints `doorbell: not set up` when neither the environment nor `env.sh` names a doorbell.
- A retried reply rings again until the recipient files the reply. Before, a reply that died after it was written and before its ring never rang on any retry.
- Registry writes take a lock, so agents registering at the same moment no longer overwrite each other's row.
- Every letter rings. `send`, and `reply` with `ack`, `nack` or `result`, ring the recipient with or without `--now`; `--now` now only marks a letter urgent. Before, a letter without `--now` landed and rang nobody.
- The doorbell is typed into the agent's pane by default. Before, typing needed `--automatic-doorbells` at setup, and without it the agent was not woken. Setup now always turns typing on and still accepts `--automatic-doorbells`. Enter can also send text already typed in that pane; only `LETTERBOX_CMUX_SUBMIT=0` stops typing, and your own `check` then says `doorbell: typing is off`.
- The ring-verb and crash-retry tests now run the paths they name, and the UUID registration suite runs in `make test`.

## [0.7.0] — 2026-11-08 (cmux edition)

- Locks are taken with the mkdir(2) syscall through perl, not the external mkdir binary: uutils coreutils 0.10.0 (Ubuntu 25.10 and later, including GitHub's ubuntu-latest) can report success under a race even when its mkdir(2) failed, so two agents could both hold one lock. Found on an Ubuntu 26.04 laptop; both places a lock is taken are fixed; regression test included (tests/test_lock_exclusivity.sh). Perl becomes a required lock dependency.

- An update by the installer now adds the Agent Letterbox skill link that setup has made since v0.5.3, so a team set up earlier gets it without running setup again. The link is made only where setup would make it, and anything already there is left alone.
- The README has an Updating section: how to check your version, and how to update an installer, Git or `npx skills` install.
- Setup's messages and the startup note (`AGENT-LETTERBOX.md`) no longer name one agent app for the extra skill link. Setup and an update print `Agent Letterbox skill also linked: <path>`.
- A doorbell timeout (`LETTERBOX_DOORBELL_TIMEOUT`) that is not whole seconds from 1 to 999 is now refused as `invalid_timeout` before any cmux command. A value such as `x` used to crash the step's time limit after the cmux command had started, so `cmux send` ran with no limit and could still type the doorbell while the ring reported `send_failed`. `letterbox ring` reports such a value the same way; before, a value such as `08` broke its own budget arithmetic and the ring reported `unconfirmed`.
- Add `letterbox query view=owed to=<agent>`: the letters an agent still owes, oldest first. These are unfiled requests and letters asking for an acknowledgement. A letter leaves the view when it is filed, not when it is answered. Each is marked `UNACKED`, `ACCEPTED-OPEN` or `ANSWERED`, with overdue and unknown-time counts, and `--limit` (default 20) marks a cut list `truncated`. It uses compatibility-v2's own answered rule. Phone letters from Agent Letter Bridge are owed until filed. When the bridge's reply file exists, the letter is marked `ANSWERED-UNPROVEN`: a reply was composed, with no proof it was delivered.
- `check` gains a map line when `LETTERBOX_NOTES_DIR` is set: how many notes, and how many have no `as-of:` cursor. `check --maps` shows, per note, how many letters in its `threads:` were sent after its cursor. Thread ids may be separated by commas or spaces, and a listed thread with no letters in the box is named, since a mistyped id would otherwise read as nothing new. With the variable unset, plain `check` prints nothing and `check --maps` says it is not set. A folder that can't be read is reported.
- Your own `check` ends with one line once it counts five or more letters: `N non-task letters to review for filing — letterbox file to tidy.` It counts letters that ask for no acknowledgement and are either not a request from a sender with a mailbox here, or a phone letter whose reply has been composed. A replied phone letter stays owed on `view=owed` until it is filed, so it is counted here and still owed there. `check` cannot tell whether a letter was read or a phone reply delivered, so the line asks for a review, not a filing. `LETTERBOX_CHECK_TIDY_AT` changes the five, and 0 turns the line off. It rings nobody and files nothing.
- Add `letterbox lint-notes`: it checks each note in `LETTERBOX_NOTES_DIR` against the letters in the box, mechanically. It reports a citation with no matching letter (`ORPHAN`) or more than one (`AMBIGUOUS`), a cited letter that has been superseded (`STALE`) or whose supersedes target is missing (`DANGLING`), a note with no `as-of:` cursor (`UNCURSORED`), and a citation alone on the line after its prose (`FORMATTING`). It never judges whether a citation supports a claim. `--json` gives machine output, and `--baseline` records the current findings so later runs report only new ones. A word in code quotes, such as a flag or a command name, is a citation only when it is a timestamp id or a letter in the box. A refusal (exit 2) names its cause in `reason`, with the scanner's codes in `issues`. If letters arrive or are filed during the scan, lint scans once more, and it reports moving mail only when it saw a change.
- `letterbox query`, `check --maps` and `lint-notes` resolve the box to its physical path first. A box reached through a symlink, such as a linked shared folder, used to come back empty, marked only `root_component_symlink`. The scanner still refuses a symlink that appears in the root during a scan.
- The skill and the startup note say that Agent Letter Bridge 0.7 files a person's letter once its reply is accepted, and that a reply or result to another agent still goes by `letterbox reply` or `letterbox send`.
- The README no longer calls the record a truth layer or ground truth. It is a shared record of what was written, under whose name, and what still stands until a later letter replaces it. It also no longer says terminal text is a handoff's only copy, or that a crashed agent gets its whole context back: it can rebuild what was written down.
- The Letterbox Method now ships with every edition: `docs/method.md` for people (the rules, the habits and the 0.7 command for each, the note header and the exit drill), and the rules and note header in the skill itself, with `references/method.md` beside it, for agents.

## v0.5.3 — 2026-10-26 (cmux edition)

- The doorbell's Enter now waits `LETTERBOX_DOORBELL_ENTER_DELAY` seconds after its text (default 2; whole seconds 0–5, 0 for no pause). An agent terminal app that detects pastes (Muse Code) swallowed the Enter sent with the text, so the doorbell sat unsubmitted while the ring reported `submitted`. An invalid value is refused as `invalid_enter_delay` before any cmux command, and the ring's time budget grows by the pause. `submitted` is documented as what it is: the multiplexer accepted the text and the Enter, not proof the agent's app submitted it.
- Setup also links the Agent Letterbox skill into `~/.claude/skills` when Claude Code is installed. Claude Code does not read `~/.agents/skills`, so a Claude Code agent never loaded the skill. An existing `~/.claude/skills/agent-letterbox` is left alone, and `LETTERBOX_SKILLS_DIR` still takes precedence.
- Running setup again to add an agent no longer unregisters the agents already running. Setup emptied the live registration registry, so every running agent's doorbell stopped until that agent registered again. It now keeps registrations whose pane is still live and drops only the dead ones.
- The installer says when it updated an existing copy, and no longer prints the first-time team setup on an update. That setup is shared, and an agent updating itself had to work out not to run it.
- `register` says when the agent's own commands still need `LETTERBOX_AGENT`. Registering a pane names it for the doorbell only, so an agent that registered itself was refused by `letterbox file` until the variable was set. `run` sets it, and then nothing is printed.

## v0.5.2 — 2026-10-25 (cmux edition)

- `letterbox reply` to a letter whose sender has no inbox now says how to answer a person who wrote through Agent Letter Bridge (`alb --reply-to <letter-id>`), instead of only "original sender has no inbox". The generated AGENT-LETTERBOX.md, the skill and the README say the same. Nothing is read from the letter beyond its validated id.

## v0.5.1 — 2026-10-24 (cmux edition)

- Add `letterbox ring <recipient> <type> <letter-id>` for Agent Letter Bridge integrated mode. It announces only a matching durable inbox letter and loads the configured box environment when a Bridge service supplies `LETTERBOX_DIR` without a doorbell setting.

## v0.5.0 — 2026-09-25 (cmux edition)

- Add read-only `letterbox query`: strict-v1 envelope cards by default and
  explicit `--compat-v2` JSON with diagnostics and scoped completeness.
- Query requires Python 3.9+ (standard library only), with an explicit refusal
  when unavailable. Registration and bounded doorbell behavior is unchanged.
- New send and reply envelopes include UTC `sent`. A send's id and header share
  one clock snapshot; stable parent-derived reply ids retain their lineage while
  `sent` records each reply's own publication time. Identical retries preserve it.
- Add `send --supersedes <id>` as a syntax-validated reference, without ownership
  lookup. This option and explicit `--re`/`--thread` refuse malformed or overlong
  values rather than sanitising them. Existing letters are unchanged.
- Refuse injected/multiline header values: session labels are bounded, deadlines
  and publication times are calendar-valid UTC, and generated/derived ids and
  inherited reply linkage are validated before publication. Invalid session
  labels are refused before a reply can create a lifecycle lock. Queries never
  silently repair malformed older envelopes.
- Bound normalized new-send slugs with room for the recipient's longest reply
  suffix, reporting the actual per-send maximum on refusal. Writer/reference
  and both query id limits use the 243-byte temporary-filename budget, retaining
  support for long v0.4.0 ids that could already be replied to. Add maximum-slug
  ACK/RESULT and actual v0.4.0-writer synthetic-fixture compatibility controls.
- Add synthetic query tests to `make ci`, with Python 3.9 and 3.13 on the Ubuntu
  and macOS workflow matrix. Matrix configuration is not a claim of a passed run.
- Distinguish symlinked root components from non-directory components. Add
  separate mutation witnesses for no-follow opens, symlink recognition, and
  pre/post-open leaf type guards.
- No archive traversal or archive verb. Transport behavior is unchanged; header
  validation is not a claim of authenticated metadata, exhaustive writer race
  hardening, or hardware crash durability.
  See [query contracts and limitations](docs/query.md).

## v0.4.0 — 2026-09-17 (cmux edition)

Release 2 doorbell contract. The ring now reports exactly one
`doorbell-outcome v=1` line per attempt — `submitted`,
`pasted_not_submitted`, or `no_live_surface` with a named reason — owned by
the helper wrapper, never by adapter prose. The typed doorbell line may
name the durable letter's sender.

- The wrapper is the sole outcome owner: the adapter's stdout is a private
  pipe; exactly one valid contract line on exit 0 forwards, anything else
  reports `unconfirmed` (`unparseable` is the consumer's verdict, never an
  emitter token).
- Two-step bounded inject (text, then Enter), each step bounded and
  classified: `send_failed`, `pasted_not_submitted enter_failed`,
  post-inject `unconfirmed`; only a proven pre-injection timeout is
  `helper_timeout` (the one retryable class).
- Runner-owned timeout sentinel: a child exiting 124 on its own is
  remapped and can never be misread as a timeout. Verified-runner check:
  missing python3 or platform CLI is `adapter_unavailable`
  (non-retryable), and without the bounder the wrapper fails closed — the
  adapter is never run unbounded.
- Ruled exit-status precedence: `submitted`/`pasted` claims after a
  nonzero exit downgrade to `unconfirmed`; a valid `no_live_surface` line
  keeps its named reason.
- Ruling-5 sender clause resolved from the durable letter (never
  `LETTERBOX_AGENT`), omitted when invalid — never `from -`.
  `doorbell-parse` accepts v02/v03/v04; a malformed ` from ` clause
  rejects the line.
- Bounds budget documented in SPEC: 1s step budget, 4×step+5s wrapper
  backstop (9s at default), strictly inside the caller's 10s deadline.
- Canonical `doorbell-outcome v=1` conformance fixtures vendored in
  `conformance/doorbell-outcome-v1/` with `SHA256SUMS`; other editions
  and Bridge vendor a frozen snapshot of these exact bytes.

## v0.3.5 — 2026-09-16 (cmux edition)

`message_body` keeps `---` lines after the envelope close, so an identical
ACK retry with a fenced body matches the stored letter. A different body
still collides. Raw body lines keep CRLF; only fence comparisons strip CR.

## v0.3.4 — 2026-09-15 (cmux edition)

Maintenance rollup of commits already on public main since v0.3.3, plus a
whitespace-only body refusal for `send` and `reply`.

Fixed
- Inbound sweeps ignore `outbox/` (bridge correspondence-in-flight under an
  agent or at the letterbox root). `check`, `token`, `file`, `read`, and
  `reply` refuse those paths. Inbox letters still file. Processed letters
  remain visible to `token` for bell-dismiss / recovery; `read` stays
  inbox-only, as before.
- Frontmatter is trusted only with a closing `---`. Malformed letters are
  skipped in scan and resolve rather than treated as mail.
- `send` and `reply` refuse an empty or whitespace-only body (spaces, tabs,
  CR, LF) with a usage hint naming how to supply one on stdin. Non-blank
  bodies keep their surrounding whitespace; the emptiness check does not
  rewrite the stored body.
- `letter_epoch` uses a mtime probe only when the complete captured stdout is
  a canonical decimal epoch (optional minus; no leading zeros). Nonzero exit
  discards stdout. GNU `stat -f` filesystem text and numeric-prefix garbage
  cannot leak into `check` arithmetic.
- User-facing token output says to dismiss the bell.

Added
- Shared guide `docs/handling-mail.md`, and an opt-in companion skill at
  `skills/handling-mail/SKILL.md`. The skill is not installed or loaded by
  anything; copy it if you want it.
- Regression for outbox sweep exclusion (`tests/test_outbox_sweep_exclusion.sh`).

## v0.3.3 — 2026-08-22 (cmux edition)

Fixed
- `letterbox cmux run` and `letterbox cmux register` failed on current cmux with
  "CMUX_SURFACE_ID is missing": cmux now exposes the surface id as a UUID, not the
  legacy `surface:N` short ref. Registration now resolves the calling pane via
  `cmux identify`'s caller object; legacy short-ref values keep working.
- A null caller (no pane ancestry — cron, stripped environments) now fails with an
  instructive error instead of silently registering the focused pane.

Added
- Regression suite for registration: UUID env, legacy short ref, bare env, and the
  null-caller/focused-pane leak.

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
