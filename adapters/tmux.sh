#!/usr/bin/env bash
# Optional tmux doorbell adapter.
# LETTERBOX_TMUX_PATTERNS is tab-separated: agent<TAB>tmux-session-name.
set -euo pipefail

to="${1:?recipient}"
type="${2:?type}"
slug="${3:?slug}"

patterns_file="${LETTERBOX_TMUX_PATTERNS:-}"
[[ -n "$patterns_file" && -r "$patterns_file" ]] || { echo 'tmux doorbell deferred: no LETTERBOX_TMUX_PATTERNS file' >&2; exit 0; }
command -v tmux >/dev/null 2>&1 || { echo 'tmux doorbell deferred: tmux is unavailable' >&2; exit 0; }

line="📬 letterbox doorbell: unacked $type in ${LETTERBOX_DIR:?set LETTERBOX_DIR}/$to/inbox/ — please check"
target=''
while IFS=$'\t' read -r agent session; do
  [[ "$agent" == "$to" && -n "$session" ]] || continue
  if tmux has-session -t "$session" 2>/dev/null; then
    target="$session"
    break
  fi
done < "$patterns_file"

[[ -n "$target" ]] || { echo "tmux doorbell deferred: no live tmux target for $to" >&2; exit 0; }

# Sending terminal input is explicit opt-in: Enter can submit unrelated text
# already typed in the target pane, exactly as with the cmux submit adapter.
if [[ "${LETTERBOX_TMUX_SUBMIT:-0}" == 1 ]]; then
  tmux send-keys -t "$target" -l "$line"
  tmux send-keys -t "$target" Enter
  printf 'tmux doorbell submitted to %s on %s\n' "$to" "$target"
else
  tmux display-message -t "$target" "$line" 2>/dev/null || true
  printf 'tmux notification sent to %s; set LETTERBOX_TMUX_SUBMIT=1 to inject the doorbell\n' "$to"
fi
