#!/usr/bin/env bash
# webhook_e2e_oracle.sh — pass/fail only from Letterbox filesystem evidence.
#
# A Hermes webhook turn (or any agent turn) is PROVEN complete only when:
#   1) the original inbound message is no longer in the recipient inbox,
#   2) that same message lives in the recipient processed/ directory,
#   3) the peer inbox holds a delivered reply (ack|nack|result) with re: = original id.
#
# Model prose, logs, or "I handled it" claims are never consulted.
#
# Usage:
#   LETTERBOX_DIR=/path/to/box \
#     ./tests/webhook_e2e_oracle.sh --agent hermes --peer planner --message-id <id>
#
# Exit 0 = PASS (disk proves completion). Exit 1 = FAIL.
set -euo pipefail

die() { printf 'oracle: %s\n' "$*" >&2; exit 1; }
pass() { printf 'oracle: PASS — %s\n' "$*"; exit 0; }

BOX="${LETTERBOX_DIR:-}"
agent=""
peer=""
message_id=""
require_type="" # optional: ack|nack|result

while [[ $# -gt 0 ]]; do
  case "$1" in
    --agent) agent="${2:?}"; shift 2;;
    --peer) peer="${2:?}"; shift 2;;
    --message-id) message_id="${2:?}"; shift 2;;
    --require-type) require_type="${2:?}"; shift 2;;
    -h|--help)
      sed -n '2,20p' "$0"
      exit 0
      ;;
    *) die "unknown option: $1";;
  esac
done

[[ -n "$BOX" && -d "$BOX" ]] || die "set LETTERBOX_DIR to an existing letterbox directory"
[[ -n "$agent" ]] || die "missing --agent"
[[ -n "$peer" ]] || die "missing --peer"
[[ -n "$message_id" ]] || die "missing --message-id"

inbox="$BOX/$agent/inbox"
processed="$BOX/$agent/processed"
peer_inbox="$BOX/$peer/inbox"

[[ -d "$inbox" && -d "$processed" && -d "$peer_inbox" ]] || die "letterbox layout incomplete under $BOX"

frontmatter_value() {
  awk -v wanted="$2" '
    NR == 1 && $0 == "---" { in_frontmatter = 1; next }
    in_frontmatter && $0 == "---" { exit }
    in_frontmatter {
      key = $0; sub(/:.*/, "", key)
      if (key == wanted) { value = $0; sub(/^[^:]*:[[:space:]]*/, "", value); print value; exit }
    }
  ' "$1"
}

# --- Rule 1: original must not remain unacked in agent inbox ---
still_in_inbox=0
if compgen -G "$inbox/*.md" > /dev/null; then
  for f in "$inbox"/*.md; do
    [[ -e "$f" ]] || continue
    id="$(frontmatter_value "$f" id)"
    if [[ "$id" == "$message_id" ]]; then
      still_in_inbox=1
      break
    fi
  done
fi
[[ "$still_in_inbox" -eq 0 ]] || die "FAIL: original message still in $agent/inbox (id=$message_id) — incomplete or hallucinated handling"

# --- Rule 2: original must be archived under processed/ ---
found_processed=""
if compgen -G "$processed/*.md" > /dev/null; then
  for f in "$processed"/*.md; do
    [[ -e "$f" ]] || continue
    id="$(frontmatter_value "$f" id)"
    if [[ "$id" == "$message_id" ]]; then
      found_processed="$f"
      break
    fi
  done
fi
[[ -n "$found_processed" ]] || die "FAIL: original id=$message_id not in $agent/processed — prose claims without archive do not count"

# --- Rule 3: peer must hold a delivered reply with re: = message_id ---
found_reply=""
found_type=""
if compgen -G "$peer_inbox/*.md" > /dev/null; then
  for f in "$peer_inbox"/*.md; do
    [[ -e "$f" ]] || continue
    re="$(frontmatter_value "$f" re)"
    from="$(frontmatter_value "$f" from)"
    to="$(frontmatter_value "$f" to)"
    typ="$(frontmatter_value "$f" type)"
    if [[ "$re" == "$message_id" && "$from" == "$agent" && "$to" == "$peer" ]]; then
      case "$typ" in
        ack|nack|result)
          if [[ -n "$require_type" && "$typ" != "$require_type" ]]; then
            continue
          fi
          found_reply="$f"
          found_type="$typ"
          break
          ;;
      esac
    fi
  done
fi
[[ -n "$found_reply" ]] || die "FAIL: no delivered ack|nack|result in $peer/inbox with re=$message_id from=$agent — model text is not evidence"

pass "processed=$(basename "$found_processed") reply=$(basename "$found_reply") type=$found_type"
