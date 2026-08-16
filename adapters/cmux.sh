#!/usr/bin/env bash
# Optional cmux doorbell adapter.
# Prefer self-registered live surfaces in LETTERBOX_CMUX_REGISTRY; fall back to
# LETTERBOX_CMUX_PATTERNS (agent<TAB>title-substring) for legacy/static agents.
set -euo pipefail

to="${1:?recipient}"
type="${2:?type}"
token="${3:-}"
command -v cmux >/dev/null 2>&1 || { echo 'letterbox: doorbell no_live_surface adapter_unavailable for '"$to" >&2; exit 0; }

line="📬 letterbox doorbell: unacked $type in ${LETTERBOX_DIR:?set LETTERBOX_DIR}/$to/inbox/ — please check"
if [[ "$token" =~ ^[0-9a-f]{8}$ ]]; then
  line="$line · $token"
fi
registry="${LETTERBOX_CMUX_REGISTRY:-$LETTERBOX_DIR/cmux-agents.tsv}"
tree="$(cmux tree --all 2>/dev/null || true)"
surface=''

if [[ -f "$registry" ]]; then
  registered="$(awk -F $'\t' -v agent="$to" '$1 == agent { print $2; exit }' "$registry")"
  if [[ "$registered" =~ ^surface:[0-9]+$ ]] && printf '%s\n' "$tree" | grep -E "${registered}([^0-9]|$)" >/dev/null; then
    surface="$registered"
  fi
fi

if [[ -z "$surface" ]]; then
  patterns_file="${LETTERBOX_CMUX_PATTERNS:-}"
  if [[ -n "$patterns_file" && -r "$patterns_file" ]]; then
    while IFS=$'\t' read -r agent pattern; do
      [[ "$agent" == "$to" && -n "$pattern" ]] || continue
      match="$(printf '%s\n' "$tree" | grep -iF -- "$pattern" | grep -o 'surface:[0-9][0-9]*' | head -1 || true)"
      [[ -n "$match" ]] && { surface="$match"; break; }
    done < "$patterns_file"
  fi
fi

[[ -n "$surface" ]] || { echo "letterbox: doorbell no_live_surface surface_not_found for $to" >&2; exit 0; }
notify_body="$type"
[[ "$token" =~ ^[0-9a-f]{8}$ ]] && notify_body="$type · $token"
cmux notify --title "letterbox → $to" --body "$notify_body" >/dev/null 2>&1 || true

# Sending terminal input is explicit opt-in: Enter can submit unrelated text
# already typed in the target pane.
if [[ "${LETTERBOX_CMUX_SUBMIT:-0}" == 1 ]]; then
  if ! cmux send --surface "$surface" "$line"; then
    echo "letterbox: doorbell no_live_surface send_failed for $to"
    exit 0
  fi
  if ! cmux send-key --surface "$surface" Enter; then
    echo "letterbox: doorbell pasted_not_submitted to $to on $surface"
    exit 0
  fi
  printf 'letterbox: doorbell submitted to %s on %s\n' "$to" "$surface"
else
  printf 'cmux notification sent for %s; set LETTERBOX_CMUX_SUBMIT=1 to inject the doorbell\n' "$to"
fi
