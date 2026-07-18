# Changelog

All notable changes to Agent Letterbox for cmux are documented here.

## [Unreleased]

### Changed

- Extracted the cmux-specific product from the former combined implementation.
- Removed tmux, desktop, and webhook experiment code from this repository.
- Added a public curl installer and copy/paste installation path, with a manual Git-install alternative.

## [0.1.0] — 2026-07-16

### Added

- Durable Letterbox CLI with atomic publish, reply-first handling, locks, and completion checks.
- Opt-in automatic cmux terminal doorbells across panels and workspaces.
- cmux self-registration for dynamically titled and duplicate agent sessions.
- One-command cmux team setup and agent launcher.
- Core, error-path, cmux adapter, registration, and bootstrap tests.
- README, setup, security, and contribution documentation.
