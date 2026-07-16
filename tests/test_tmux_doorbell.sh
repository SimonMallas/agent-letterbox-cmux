#!/usr/bin/env bash
# Live disposable tmux proof for the opt-in automatic doorbell.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
adapter="$root/adapters/tmux.sh"
session="letterbox-doorbell-test-$$"
tmp="$(mktemp -d)"
trap 'tmux kill-session -t "$session" 2>/dev/null || true; rm -rf "$tmp"' EXIT

command -v tmux >/dev/null 2>&1 || { echo 'tmux doorbell test: SKIP (tmux unavailable)'; exit 0; }
printf 'receiver\t%s\n' "$session" > "$tmp/patterns.tsv"
# cat echoes received input into the pane, allowing capture-pane verification.
tmux new-session -d -s "$session" 'cat'

LETTERBOX_DIR="$tmp/box" \
LETTERBOX_TMUX_PATTERNS="$tmp/patterns.tsv" \
LETTERBOX_TMUX_SUBMIT=1 \
"$adapter" receiver delegate smoke-test

sleep 1
# capture-pane wraps long terminal lines; compare after removing visual wraps.
received="$(tmux capture-pane -p -t "$session" | tr -d '\n')"
expected="📬 letterbox doorbell: unacked delegate in $tmp/box/receiver/inbox/ — please check"
printf '%s\n' "$received" | grep -F "$expected" >/dev/null
printf '%s\n' 'tmux automatic doorbell test: PASS'
