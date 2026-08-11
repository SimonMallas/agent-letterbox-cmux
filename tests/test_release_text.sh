#!/usr/bin/env bash
# test_release_text.sh — release documentation must not drift from helper behavior.
#
# For each observable helper behavior, the public docs must carry the matching
# compatibility wording and must not carry contradiction wording. Each assertion
# reports SKIP when its behavior probe does not fire, so a pass is never vacuous.
set -uo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"; cd "$root"
helper="bin/letterbox"
fails=0
fail() { printf 'FAIL: %s\n' "$*" >&2; fails=$((fails + 1)); }
pass() { printf 'PASS: %s\n' "$*"; }
skip() { printf 'SKIP: %s\n' "$*"; }

[[ -f "$helper" ]] || { fail "helper missing: $helper"; exit 1; }
for doc in README.md CHANGELOG.md SPEC.md; do
  [[ -f "$doc" ]] || fail "doc missing: $doc"
done

# --- Behavior probes (single source of truth: the helper) ---
grep -q 'thread: %s' "$helper" && THREAD_EMITTED=1 || THREAD_EMITTED=0
grep -q 'use letterbox reply for ownership replies' "$helper" && REPLY_GUARD=1 || REPLY_GUARD=0
grep -q 'delegate letters require --ack' "$helper" && ACK_GUARD=1 || ACK_GUARD=0

# --- 1. thread field => additive-compat wording required, no-format-change claims forbidden ---
if (( THREAD_EMITTED )); then
  for doc in README.md CHANGELOG.md SPEC.md; do
    if grep -inE 'no message[- ]format change|message[- ]format (is |remains )?unchanged' "$doc" >/dev/null; then
      fail "$doc claims message format is unchanged, but the helper emits a thread field"
    elif ! { grep -qi 'thread' "$doc" && grep -qiE 'additive|optional' "$doc" && grep -qiE 'remain valid|ignore unknown|backward.?compat' "$doc"; }; then
      fail "$doc lacks additive/optional-thread compatibility wording (thread + additive|optional + remain-valid|ignore-unknown)"
    fi
  done
  (( fails == 0 )) && pass "thread emission documented as additive/optional and compatible in README/CHANGELOG/SPEC"
else
  skip "helper does not emit thread — assertion dormant"
fi

# --- 2. freeform-ownership-reply refusal => reply replacement documented ---
if (( REPLY_GUARD )); then
  ok=1
  grep -q 'letterbox reply' CHANGELOG.md || { fail "CHANGELOG.md does not document the letterbox reply replacement"; ok=0; }
  grep -q 'letterbox reply' README.md    || { fail "README.md does not document the letterbox reply replacement"; ok=0; }
  (( ok )) && pass "ownership-reply refusal documented in CHANGELOG/README"
else
  skip "helper has no ownership-reply refusal — assertion dormant"
fi

# --- 3. delegate requires --ack => documented ---
if (( ACK_GUARD )); then
  ok=1
  grep -q -- '--ack' CHANGELOG.md || { fail "CHANGELOG.md does not document delegate --ack requirement"; ok=0; }
  grep -q -- '--ack' README.md    || { fail "README.md does not document delegate --ack requirement"; ok=0; }
  (( ok )) && pass "delegate --ack requirement documented in CHANGELOG/README"
else
  skip "helper has no delegate --ack guard — assertion dormant"
fi

if (( fails > 0 )); then
  printf 'release-text: FAIL (%d)\n' "$fails" >&2
  exit 1
fi
printf 'release-text: PASS\n'
