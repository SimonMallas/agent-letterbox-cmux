#!/usr/bin/env bash
# Optional tmux doorbell adapter.
# LETTERBOX_TMUX_PATTERNS is tab-separated: agent<TAB>session-or-window-pattern.
# Multiple rows for an agent provide fallback patterns.
set -euo pipefail

to="${1:?recipient}"
type="${2:?type}"
slug="${3:?slug}"

patterns_file="${LETTERBOX_TMUX_PATTERNS:-}"
[[ -n "$patterns_file" && -r "$patterns_file" ]] || { echo 'tmux doorbell deferred: no LETTERBOX_TMUX_PATTERNS file' >&2; exit 0; }
command -v tmux >/dev/null 2>&1 || { echo 'tmux doorbell deferred: tmux is unavailable' >&2; exit 0; }

line="📬 letterbox doorbell: unacked $type in ${LETTERBOX_DIR:?set LETTERBOX_DIR}/$to/inbox/ — please check"

target=''
while IFS=$'\t' read -r agent pattern; do
  [[ "$agent" == "$to" && -n "$pattern" ]] || continue
  if tmux has-session -t "$pattern" 2>/dev/null; then
    target="$pattern"
    break
  fi
done < "$patterns_file"

[[ -n "$target" ]] || { echo "tmux doorbell deferred: no live tmux target for $to" >&2; exit 0; }

# Notification only (display-message alerts the human in the session).
# This adapter signals visibility only — it does not prove the agent checked its inbox.
tmux display-message -t "$target" "$line" 2>/dev/null || true
printf 'tmux notification sent to %s on %s\n' "$to" "$target"
