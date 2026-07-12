#!/usr/bin/env bash
# webhook_e2e_harness.sh — deterministic, mockable proof for webhook-bridge completion.
#
# Does NOT create Hermes webhooks, watchers, or change Hermes config.
# It simulates the *Letterbox outcomes* a webhook-triggered turn must produce,
# and proves the oracle rejects the prior failure mode: agent claims done
# without delivering ACK/result or archiving the original.
#
# Scenarios:
#   A) honest handler  — letterbox reply (publish + archive)  → oracle PASS
#   B) hallucinated    — prose "completion" only, no bus ops → oracle FAIL (expected)
#   C) partial         — reply delivered via send, no archive → oracle FAIL (expected)
#
# Usage: ./tests/webhook_e2e_harness.sh
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
helper="$root/bin/letterbox"
oracle="$root/tests/webhook_e2e_oracle.sh"

box="$(mktemp -d "${TMPDIR:-/tmp}/letterbox-webhook-e2e.XXXXXX")"
trap 'rm -rf "$box"' EXIT

export LETTERBOX_DIR="$box"
export PATH="$root/bin:$PATH"

lb() {
  # usage: lb <agent> <letterbox-args...>
  local agent="$1"; shift
  LETTERBOX_DIR="$box" LETTERBOX_AGENT="$agent" letterbox "$@"
}

printf '== harness: init disposable letterbox at %s ==\n' "$box"
LETTERBOX_DIR="$box" letterbox init planner hermes

# Shared: planner sends a requires_ack delegate (the letter that must be handled).
# Prints: <message-path>|<id>
send_delegate() {
  local slug="$1"
  # letterbox prints "sent: …" on stdout — keep harness pair line pure.
  printf '%s\n' "GOAL: Webhook e2e probe ($slug). DONE-WHEN: ACK on disk and archive original." |
    lb planner send hermes delegate "$slug" --ack >/dev/null
  local message id
  message="$(find "$box/hermes/inbox" -maxdepth 1 -name '*.md' -type f | sort | tail -1)"
  test -n "$message" && test -f "$message"
  id="$(awk -F': ' '$1 == "id" { print $2; exit }' "$message")"
  test -n "$id"
  printf '%s|%s\n' "$message" "$id"
}

expect_oracle_pass() {
  local id="$1" label="$2"
  if ! LETTERBOX_DIR="$box" bash "$oracle" --agent hermes --peer planner --message-id "$id" --require-type ack; then
    printf 'harness: FAIL (%s): oracle should PASS\n' "$label" >&2
    exit 1
  fi
  printf 'harness: ok — %s oracle PASS\n' "$label"
}

expect_oracle_fail() {
  local id="$1" label="$2"
  if LETTERBOX_DIR="$box" bash "$oracle" --agent hermes --peer planner --message-id "$id" >/dev/null 2>&1; then
    printf 'harness: FAIL (%s): oracle should FAIL (hallucinated/partial completion)\n' "$label" >&2
    exit 1
  fi
  printf 'harness: ok — %s oracle correctly FAILED\n' "$label"
}

# ---------------------------------------------------------------------------
# A) Honest webhook-turn simulation: real letterbox reply
# ---------------------------------------------------------------------------
printf '\n== A) honest handler (letterbox reply) ==\n'
pair_a="$(send_delegate "honest-path")"
msg_a="${pair_a%%|*}"
id_a="${pair_a##*|}"
printf 'Accepted via letterbox reply (webhook turn simulation).\n' |
  lb hermes reply "$msg_a" ack e2e-honest >/dev/null
expect_oracle_pass "$id_a" "A-honest"

# ---------------------------------------------------------------------------
# B) Hallucinated completion: model prose / log only (the prior failure mode)
# ---------------------------------------------------------------------------
printf '\n== B) hallucinated completion (prose only — no letterbox ops) ==\n'
pair_b="$(send_delegate "hallucinated-path")"
msg_b="${pair_b%%|*}"
id_b="${pair_b##*|}"
mkdir -p "$box/hermes/session-notes"
cat > "$box/hermes/session-notes/claimed-complete.md" <<EOF
I checked the Agent Letterbox inbox and handled all messages.
Original id: $id_b
Status: complete
EOF
# Critically: do NOT call letterbox reply/done; leave original in inbox.
test -f "$msg_b"
expect_oracle_fail "$id_b" "B-hallucinated"
# Isolate next scenario: drop unhandled letter (does not satisfy protocol).
rm -f "$msg_b"
rm -f "$box/hermes/session-notes/claimed-complete.md"

# ---------------------------------------------------------------------------
# C) Partial handling: peer gets a reply file, original never archived
# ---------------------------------------------------------------------------
printf '\n== C) partial handling (delivered reply, no archive) ==\n'
pair_c="$(send_delegate "partial-path")"
msg_c="${pair_c%%|*}"
id_c="${pair_c##*|}"
printf 'Ack body without archive.\n' |
  lb hermes send planner ack e2e-partial --re "$id_c" >/dev/null
test -f "$msg_c"
expect_oracle_fail "$id_c" "C-partial"

printf '\nwebhook e2e harness: PASS\n'
printf 'Criteria: disk ACK/result + processed original only — never model prose.\n'
