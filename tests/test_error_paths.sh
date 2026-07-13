#!/usr/bin/env bash
# Dependency-free error-path tests using only the public letterbox CLI.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
letterbox="$root/bin/letterbox"
box="$(mktemp -d)"
trap 'rm -rf "$box"' EXIT

lb() {
  local agent="$1"; shift
  LETTERBOX_DIR="$box" LETTERBOX_AGENT="$agent" "$letterbox" "$@"
}

printf '%s\n' '=== Setup ==='
LETTERBOX_DIR="$box" "$letterbox" init alpha beta >/dev/null

printf '%s\n' '=== Invalid delivered reply cannot archive original ==='
printf 'Review this request.\n' | lb alpha send beta delegate error-reply --ack >/dev/null
message=("$box/beta/inbox"/*.md)
test "${#message[@]}" = 1
message_id="$(awk -F': ' '$1 == "id" { print $2; exit }' "${message[0]}")"
cat > "$box/alpha/inbox/bad-reply.md" <<EOF
---
id: bad-reply
from: beta
to: wrong-recipient
type: ack
re: $message_id
priority: next
requires_ack: false
deadline:
---
Invalid recipient.
EOF
if lb beta done "${message[0]}" --reply "$box/alpha/inbox/bad-reply.md"; then
  echo 'FAIL: misdirected reply was accepted' >&2
  exit 1
fi
test -f "${message[0]}"
printf '%s\n' 'PASS'

printf '%s\n' '=== Unknown agent fails ==='
if LETTERBOX_DIR="$box" LETTERBOX_AGENT=gamma "$letterbox" check; then
  echo 'FAIL: unknown agent was accepted' >&2
  exit 1
fi
printf '%s\n' 'PASS'

printf '%s\n' '=== Lock ownership and contention ==='
lb alpha lock shared-resource >/dev/null
if lb beta lock shared-resource; then
  echo 'FAIL: second lock owner was accepted' >&2
  exit 1
fi
if lb beta unlock shared-resource; then
  echo 'FAIL: non-owner unlock was accepted' >&2
  exit 1
fi
lb alpha unlock shared-resource >/dev/null
printf '%s\n' 'PASS'

printf '%s\n' 'error-path tests: PASS'
