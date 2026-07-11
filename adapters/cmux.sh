#!/usr/bin/env bash
# Optional cmux doorbell adapter.
# AGENT_BUS_CMUX_PATTERNS is a tab-separated file: agent<TAB>title-substring.
# Multiple rows for the same agent provide fallback title markers.
set -euo pipefail

to="${1:?recipient}"; type="${2:?type}"; slug="${3:?slug}"
patterns_file="${AGENT_BUS_CMUX_PATTERNS:-}"
[[ -n "$patterns_file" && -r "$patterns_file" ]] || { echo 'cmux doorbell deferred: no AGENT_BUS_CMUX_PATTERNS file' >&2; exit 0; }
command -v cmux >/dev/null 2>&1 || { echo 'cmux doorbell deferred: cmux is unavailable' >&2; exit 0; }
line="📬 agent-bus doorbell: unacked $type in ${AGENT_BUS_DIR:?set AGENT_BUS_DIR}/$to/inbox/ — please check"
surface=''
while IFS=$'\t' read -r agent pattern; do
  [[ "$agent" == "$to" && -n "$pattern" ]] || continue
  match="$(cmux tree --all 2>/dev/null | grep -iF -- "$pattern" | grep -o 'surface:[0-9][0-9]*' | head -1 || true)"
  [[ -n "$match" ]] && { surface="$match"; break; }
done < "$patterns_file"
[[ -n "$surface" ]] || { echo "cmux doorbell deferred: no live surface for $to" >&2; exit 0; }
cmux send --surface "$surface" "$line"
cmux send-key --surface "$surface" Enter
cmux notify --title "agent-bus → $to" --body "$type: $slug" >/dev/null 2>&1 || true
printf 'cmux doorbell sent to %s on %s\n' "$to" "$surface"
