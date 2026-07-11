#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
bus="$(mktemp -d)"
trap 'rm -rf "$bus"' EXIT
helper="$root/bin/agent-bus"

AGENT_BUS_DIR="$bus" "$helper" init alpha beta
printf 'Please review this.\n' | AGENT_BUS_DIR="$bus" AGENT_BUS_AGENT=alpha "$helper" send beta delegate review --ack
messages=("$bus/beta/inbox"/*.md)
test "${#messages[@]}" = 1
message="${messages[0]}"
id="$(awk -F': ' '$1 == "id" { print $2; exit }' "$message")"
test -n "$id"
test "$(find "$bus/beta/inbox" -name '.*.tmp.*' | wc -l | tr -d ' ')" = 0

cat > "$bus/alpha/inbox/reply.md" <<EOF
---
id: reply-1
from: beta
to: alpha
type: ack
re: $id
priority: next
requires_ack: false
deadline:
---
Accepted.
EOF
AGENT_BUS_DIR="$bus" AGENT_BUS_AGENT=beta "$helper" done "$message" --reply "$bus/alpha/inbox/reply.md"

(AGENT_BUS_DIR="$bus" AGENT_BUS_AGENT=alpha "$helper" lock shared-resource >"$bus/alpha.lock" 2>&1) & one=$!
(AGENT_BUS_DIR="$bus" AGENT_BUS_AGENT=beta "$helper" lock shared-resource >"$bus/beta.lock" 2>&1) & two=$!
wait "$one" || true
wait "$two" || true
test "$(grep -l '^locked:' "$bus"/*.lock | wc -l | tr -d ' ')" = 1
printf 'smoke test: PASS\n'
