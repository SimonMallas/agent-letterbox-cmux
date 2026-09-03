#!/usr/bin/env bash
# Outbox letters must never be reported, rung, filed, or archived as inbound.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
box="$(mktemp -d)"
trap 'rm -rf "$box"' EXIT
helper="$root/bin/letterbox"
lb() { LETTERBOX_DIR="$box" LETTERBOX_AGENT="${LETTERBOX_AGENT:-}" "$helper" "$@"; }

fail() { echo "FAIL: $*" >&2; exit 1; }

LETTERBOX_DIR="$box" "$helper" init alpha beta

# Ordinary inbound still works.
printf 'Please review this.\n' | LETTERBOX_AGENT=alpha lb send beta delegate review --ack
inbox_letter=("$box/beta/inbox"/*.md)
[[ ${#inbox_letter[@]} -eq 1 ]] || fail "expected one inbox letter"
inbox_id="$(awk -F': ' '$1 == "id" { print $2; exit }' "${inbox_letter[0]}")"
[[ -n "$inbox_id" ]] || fail "inbox letter missing id"

# Plant a lookalike task in outbox. Do not go through send.
mkdir -p "$box/beta/outbox"
out_id="2026-09-03T120000-alpha-delegate-outbox-plant-aabbccdd"
cat > "$box/beta/outbox/${out_id}.md" <<EOF
---
id: ${out_id}
from: alpha
to: beta
type: delegate
re:
priority: now
requires_ack: true
deadline:
---
This is outbound correspondence. Inbound sweeps must ignore it.
EOF

# Empty outbox on another agent must not break check.
mkdir -p "$box/alpha/outbox"

check_out="$(LETTERBOX_AGENT=beta lb check 2>&1)" || fail "check died"
printf '%s\n' "$check_out" | grep -q "inbox: 1 message" || fail "check count should be 1, got: $check_out"
printf '%s\n' "$check_out" | grep -qi "aabbccdd\|outbox-plant" && fail "check reported an outbox letter"

# Token of the outbox id is not inbound work (editions without token skip).
tok_rc=0
tok_out="$(LETTERBOX_AGENT=beta lb token aabbccdd 2>&1)" || tok_rc=$?
if printf '%s\n' "$tok_out" | grep -qiE 'unknown command|usage: letterbox'; then
  :
elif printf '%s\n' "$tok_out" | grep -qi "unknown-token"; then
  :
else
  fail "outbox token should be unknown (rc=$tok_rc): $tok_out"
fi

# Path-based file/read/reply must refuse and leave the file in outbox.
out_path="$box/beta/outbox/${out_id}.md"
if LETTERBOX_AGENT=beta lb file "$out_path" >/dev/null 2>&1; then
  fail "file accepted an outbox path"
fi
if LETTERBOX_AGENT=beta lb read "$out_path" >/dev/null 2>&1; then
  fail "read accepted an outbox path"
fi
if printf 'no\n' | LETTERBOX_AGENT=beta lb reply "$out_path" nack no-outbox >/dev/null 2>&1; then
  fail "reply accepted an outbox path"
fi
[[ -f "$out_path" ]] || fail "outbox letter was moved"
[[ ! -e "$box/beta/processed/${out_id}.md" ]] || fail "outbox letter archived as inbound"

# Inbox letter still files via the normal result path.
printf 'done\n' | LETTERBOX_AGENT=beta lb reply "${inbox_letter[0]}" result accept-review
[[ -f "$box/beta/processed/$(basename "${inbox_letter[0]}")" ]] || fail "inbox letter was not archived"
[[ ! -e "${inbox_letter[0]}" ]] || fail "inbox letter still in inbox"

echo "outbox-sweep-exclusion: PASS"
exit 0
