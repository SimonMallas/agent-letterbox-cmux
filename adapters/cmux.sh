#!/usr/bin/env bash
# Optional cmux doorbell adapter.
# LETTERBOX_CMUX_PATTERNS is tab-separated: agent<TAB>title-substring.
# Multiple rows for an agent provide fallback title markers.
set -euo pipefail

to="${1:?recipient}"; type="${2:?type}"; slug="${3:?slug}"
patterns_file="${LETTERBOX_CMUX_PATTERNS:-}"
[[ -n "$patterns_file" && -r "$patterns_file" ]] || { echo 'cmux doorbell deferred: no LETTERBOX_CMUX_PATTERNS file' >&2; exit 0; }
command -v cmux >/dev/null 2>&1 || { echo 'cmux doorbell deferred: cmux is unavailable' >&2; exit 0; }
line="📬 letterbox doorbell: unacked $type in ${LETTERBOX_DIR:?set LETTERBOX_DIR}/$to/inbox/ — please check"
surface=''
while IFS=$'\t' read -r agent pattern; do
  [[ "$agent" == "$to" && -n "$pattern" ]] || continue
  match="$(cmux tree --all 2>/dev/null | grep -iF -- "$pattern" | grep -o 'surface:[0-9][0-9]*' | head -1 || true)"
  [[ -n "$match" ]] && { surface="$match"; break; }
done < "$patterns_file"
[[ -n "$surface" ]] || { echo "cmux doorbell deferred: no live surface for $to" >&2; exit 0; }
cmux notify --title "letterbox → $to" --body "$type: $slug" >/dev/null 2>&1 || true
if [[ "${LETTERBOX_CMUX_SUBMIT:-0}" == 1 ]]; then
  cmux send --surface "$surface" "$line"
  cmux send-key --surface "$surface" Enter
  printf 'cmux doorbell submitted to %s on %s\n' "$to" "$surface"
else
  printf 'cmux notification sent for %s; set LETTERBOX_CMUX_SUBMIT=1 to inject the doorbell\n' "$to"
fi
