#!/usr/bin/env bash
# Claude Code reads ~/.claude/skills, not ~/.agents/skills. Setup links the
# skill there too when Claude Code is installed, never replaces what is there,
# and does nothing when Claude Code is absent or LETTERBOX_SKILLS_DIR is set.
set -euo pipefail

EDITION="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
ED=cmux
T="$(mktemp -d /tmp/lb-claude-skill.XXXXXX)"
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/stub"
for b in tmux cmux zellij herdr; do printf '#!/bin/sh\nexit 0\n' > "$T/stub/$b"; chmod +x "$T/stub/$b"; done

pass=0
ok() { printf 'PASS: %s\n' "$1"; pass=$((pass + 1)); }
bad() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }
setup() { # home [extra env...]
  local home="$1"; shift
  env -i HOME="$home" PATH="$T/stub:/usr/bin:/bin" "$@" \
    "$EDITION/bin/letterbox" "$ED" setup --agents alpha --dir "$home/box" 2>&1
}
source_dir="$(cd "$EDITION/skills/agent-letterbox" && pwd)"

H="$T/with-claude"; mkdir -p "$H/.claude"
out="$(setup "$H")"
[[ -L "$H/.claude/skills/agent-letterbox" ]] || bad "Claude Code gets the skill ($out)"
[[ "$(cd "$H/.claude/skills/agent-letterbox" && pwd -P)" == "$(cd "$source_dir" && pwd -P)" ]] \
  || bad "the link points at the bundled skill"
[[ "$out" == *"skill linked for Claude Code"* ]] || bad "setup says so ($out)"
ok "linked into ~/.claude/skills when Claude Code is installed"
setup "$H" >/dev/null || bad "running setup again is fine"
ok "re-running setup is idempotent"

H="$T/own-skill"; mkdir -p "$H/.claude/skills/agent-letterbox"
printf 'mine\n' > "$H/.claude/skills/agent-letterbox/SKILL.md"
out="$(setup "$H")" || bad "setup does not fail on an existing skill ($out)"
[[ "$(cat "$H/.claude/skills/agent-letterbox/SKILL.md")" == mine && ! -L "$H/.claude/skills/agent-letterbox" ]] \
  || bad "an existing skill is left alone"
[[ "$out" == *"left alone"* ]] || bad "and setup says so ($out)"
ok "an existing ~/.claude skill is never replaced"

H="$T/no-claude"; mkdir -p "$H"
setup "$H" >/dev/null
[[ ! -e "$H/.claude" ]] || bad "nothing is created without Claude Code"
ok "no Claude Code, no ~/.claude"

H="$T/custom-dir"; mkdir -p "$H/.claude"
setup "$H" LETTERBOX_SKILLS_DIR="$T/skills" >/dev/null
[[ ! -e "$H/.claude/skills/agent-letterbox" ]] || bad "a chosen skills dir is respected"
ok "LETTERBOX_SKILLS_DIR is respected"

printf 'claude skill link suite: PASS (%s)\n' "$pass"
