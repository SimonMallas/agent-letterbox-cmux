# Contributing

Thanks for interest in Agent Letterbox. This guide is for people improving the **protocol, CLI, adapters, tests, and docs**.

## Scope of contributions (v0.1)

**In scope**

- Core CLI (`bin/letterbox`) and SPEC fidelity
- Optional terminal doorbell adapters (cmux, tmux, desktop notify) with safe defaults
- Tests, docs, packaging for a small filesystem-first release
- Clarifying failure modes and operator safety

**Out of scope for v0.1 (see ROADMAP.md)**

- Autonomous desktop-agent turns
- Webhook-triggered unattended Letterbox processing
- Persistent inbox watchers / retry supervisors as product features
- Required servers, databases, dashboards, or MCP dependencies

Research artifacts (e.g. Hermes skill notes, filesystem oracle harness) may live in-tree; do not market them as supported unattended automation until a new roadmap milestone says so.

## Development setup

Requirements: Bash and standard macOS/Linux userland.

```bash
git clone <this-repo>
cd agent-letterbox
chmod +x bin/letterbox adapters/*.sh tests/*.sh
export PATH="$PWD/bin:$PATH"
```

## Tests

Run the dependency-free suite before opening a PR:

```bash
./tests/smoke.sh
./tests/cmux-doorbell-safety.sh
./tests/test_desktop_adapter.sh
./tests/webhook_e2e_harness.sh
# if Python is available for skill fixture tests:
python3 tests/test_skill_prompt.py
```

Expect each script to print an explicit **PASS** (or pytest OK). CI runs the shell harnesses on Ubuntu and macOS.

## Coding guidelines

1. **Surgical changes** — prefer the smallest fix that matches the SPEC.
2. **No new hard dependencies** in core — keep the CLI Bash-only.
3. **Fail open for doorbells** — missing adapter config must not block durable delivery.
4. **Reply-first** — archival helpers must not archive without a delivered reply when the protocol requires one.
5. **Do not put task content in doorbells** — generic “please check inbox” only.
6. **Document unsafe opt-ins** (e.g. terminal keystroke submit) with defaults **off**.

## Pull requests

1. Fork / branch from `main` (or the branch the maintainers specify while private).
2. Keep PRs focused; separate docs-only from behavior changes when practical.
3. Update `CHANGELOG.md` under `[Unreleased]` for user-visible changes.
4. Describe *what* and *why*; note any SPEC impact.
5. Do not commit secrets, local `LETTERBOX_DIR` contents, or machine-specific paths.

## Protocol changes

Edits that change message format, handling rules, or layout require:

- An update to [SPEC.md](SPEC.md)
- Tests that lock the new behavior
- A CHANGELOG entry

Breaking protocol changes should bump the documented protocol version intentionally—not silently.

## Security

See [SECURITY.md](SECURITY.md). Do not file public issues for vulnerabilities.

## License

By contributing, you agree that your contributions are licensed under the MIT License (see [LICENSE](LICENSE)).
