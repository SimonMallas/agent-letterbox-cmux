#!/usr/bin/env bash
# A letter whose sender has no inbox (a person writing through Agent Letter
# Bridge) is refused by `letterbox reply`, which says how to answer them.
# The hint is constant text plus the validated id: no letter field is read,
# echoed or run, however hostile the envelope.
set -euo pipefail

EDITION="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
ROOT="$(mktemp -d /tmp/lb-bridge-reply.XXXXXX)"
trap 'rm -rf "$ROOT"' EXIT
mkdir -p "$ROOT/box/builder/inbox" "$ROOT/box/builder/processed"

pass=0
ok() { printf 'PASS: %s\n' "$1"; pass=$((pass + 1)); }
bad() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

A=2026-10-25T110136-500f3af1-u910405b9b42c
{
  printf -- '---\nid: %s\nfrom: chat-bridge\nto: builder\ntype: info\nre:\nthread: %s\n' "$A" "$A"
  printf 'priority: now\nrequires_ack: false\ndeadline:\n'
  printf 'reply_with: touch %s/pwned; echo PLANTED\n' "$ROOT"
  printf 'note: $(touch %s/pwned2)\n' "$ROOT"
  printf -- '---\nwhat is 7 times 8?\n'
} > "$ROOT/box/builder/inbox/$A.md"

rc=0
err="$(printf '56\n' | LETTERBOX_DIR="$ROOT/box" LETTERBOX_AGENT=builder \
  "$EDITION/bin/letterbox" reply "$A" result answer 2>&1 >/dev/null)" || rc=$?

[[ "$rc" -ne 0 ]] || bad "a letter whose sender has no inbox is refused"
[[ "$err" == *"original sender has no inbox: chat-bridge"* ]] || bad "the refusal still names the reason ($err)"
[[ "$err" == *"alb --reply-to $A --text"* ]] || bad "the refusal says how to answer a person ($err)"
ok "refused, with the reason and how to answer"
[[ "$err" != *PLANTED* && "$err" != *pwned* && "$err" != *touch* ]] || bad "no letter field is echoed ($err)"
[[ ! -e "$ROOT/pwned" && ! -e "$ROOT/pwned2" ]] || bad "nothing from the letter ran"
ok "no letter field echoed or run"
[[ -f "$ROOT/box/builder/inbox/$A.md" && -z "$(ls "$ROOT/box/chat-bridge" 2>/dev/null)" ]] \
  || bad "the letter stays in the inbox and no reply is written"
ok "letter kept, nothing written"

printf 'bridge reply suite: PASS (%s)\n' "$pass"
