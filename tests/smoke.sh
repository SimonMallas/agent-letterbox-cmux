#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
box="$(mktemp -d)"
trap 'rm -rf "$box"' EXIT
helper="$root/bin/letterbox"

LETTERBOX_DIR="$box" "$helper" init alpha beta
printf 'Please review this.\n' | LETTERBOX_DIR="$box" LETTERBOX_AGENT=alpha "$helper" send beta delegate review --ack
messages=("$box/beta/inbox"/*.md)
test "${#messages[@]}" = 1
message="${messages[0]}"
id="$(awk -F': ' '$1 == "id" { print $2; exit }' "$message")"
test -n "$id"
test "$(find "$box/beta/inbox" -name '.*.tmp.*' | wc -l | tr -d ' ')" = 0

# A real reply publishes to alpha's inbox before archiving beta's inbound letter.
printf 'Accepted.\n' | LETTERBOX_DIR="$box" LETTERBOX_AGENT=beta "$helper" reply "$message" ack accept-review
reply=("$box/alpha/inbox"/*.md)
test "${#reply[@]}" = 1
test "$(awk -F': ' '$1 == "re" { print $2; exit }' "${reply[0]}")" = "$id"
test ! -e "$message"
test "$(find "$box/beta/processed" -name '*.md' -type f | wc -l | tr -d ' ')" = 1

# A correctly formatted reply outside the sender inbox cannot satisfy `done`.
printf 'Please review another item.\n' | LETTERBOX_DIR="$box" LETTERBOX_AGENT=alpha "$helper" send beta delegate second-review --ack
second=("$box/beta/inbox"/*.md)
second_id="$(awk -F': ' '$1 == "id" { print $2; exit }' "${second[0]}")"
cat > "$box/undelivered.md" <<EOF
---
id: rogue
from: beta
to: alpha
type: ack
re: $second_id
priority: next
requires_ack: false
deadline:
---
Not delivered.
EOF
if LETTERBOX_DIR="$box" LETTERBOX_AGENT=beta "$helper" done "${second[0]}" --reply "$box/undelivered.md"; then
  echo 'done accepted an undelivered reply' >&2; exit 1
fi

(LETTERBOX_DIR="$box" LETTERBOX_AGENT=alpha "$helper" lock shared-resource >"$box/alpha.lock" 2>&1) & one=$!
(LETTERBOX_DIR="$box" LETTERBOX_AGENT=beta "$helper" lock shared-resource >"$box/beta.lock" 2>&1) & two=$!
wait "$one" || true
wait "$two" || true
test "$(grep -l '^locked:' "$box"/*.lock | wc -l | tr -d ' ')" = 1
printf 'smoke test: PASS\n'
