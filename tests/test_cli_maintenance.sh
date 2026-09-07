#!/usr/bin/env bash
# Public-entrypoint regressions: token glance-status and empty-body stdin hints.
# Disposable LETTERBOX_DIR. Inert doorbell. Never touches live mail.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
letterbox="${LETTERBOX_BIN:-$root/bin/letterbox}"
box="$(mktemp -d "${TMPDIR:-/tmp}/lb-cli-maint.XXXXXX")"
ringlog="$box/ring.log"
trap 'rm -rf "$box"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "PASS: $*"; }

lb() {
  local agent="$1"; shift
  LETTERBOX_DIR="$box" LETTERBOX_AGENT="$agent" LETTERBOX_DOORBELL="$box/doorbell.sh" \
    RINGLOG="$ringlog" "$letterbox" "$@"
}

cat > "$box/doorbell.sh" <<'EOF'
#!/usr/bin/env bash
echo "RING $*" >> "${RINGLOG}"
EOF
chmod +x "$box/doorbell.sh"
: > "$ringlog"

LETTERBOX_DIR="$box" "$letterbox" init alpha beta >/dev/null

put() {
  local agent="$1" id="$2"
  mkdir -p "$box/$agent/inbox" "$box/$agent/processed"
  cat > "$box/$agent/inbox/$id.md" <<EOF
---
id: $id
from: beta
to: $agent
type: info
re:
priority: next
requires_ack: false
deadline:
---
CONFIDENTIAL-BODY-MUST-NOT-APPEAR
EOF
}

plat=""
for c in cmux tmux herdr zellij; do
  if [[ -x "$root/adapters/$c.sh" ]]; then plat="$c"; break; fi
done
[[ -n "$plat" ]] || fail "no platform adapter"

# --- token states ---
put alpha "2026-09-07T010000-beta-info-open-abcd1234"
: > "$ringlog"
out="$(lb alpha token abcd1234 2>&1)" || fail "unhandled token rc"
[[ "$out" == "unhandled — check" ]] || fail "unhandled output: $out"
echo "$out" | grep -q CONFIDENTIAL && fail "token leaked body"
[[ -f "$box/alpha/inbox/2026-09-07T010000-beta-info-open-abcd1234.md" ]] || fail "unhandled mutated inbox"
[[ ! -s "$ringlog" ]] || fail "token rang doorbell: $(cat "$ringlog")"
pass "token unhandled — check (no body, no ring, no mutation)"

lb alpha file abcd1234 >/dev/null
out="$(lb alpha token abcd1234 2>&1)" || fail "filed token rc"
[[ "$out" == "already filed — dismiss bell" ]] || fail "filed output: $out"
[[ -f "$box/alpha/processed/2026-09-07T010000-beta-info-open-abcd1234.md" ]] || fail "filed letter missing"
pass "token already filed — dismiss bell"

out="$(lb alpha token 00000000 2>&1)" || fail "unknown token rc nonzero"
[[ "$out" == "unknown-token — no letter; ignore" ]] || fail "unknown output: $out"
pass "token unknown"

if out="$(lb alpha token ABCD1234 2>&1)"; then fail "uppercase token accepted"; fi
echo "$out" | grep -q 'token must be 8 lowercase hex' || fail "malformed uppercase: $out"
if out="$(lb alpha token abcd123 2>&1)"; then fail "short token accepted"; fi
if out="$(lb alpha token abcd12345 2>&1)"; then fail "long token accepted"; fi
if out="$(lb alpha token 'abcd12zz' 2>&1)"; then fail "non-hex token accepted"; fi
pass "token malformed/invalid refuses"

put alpha "2026-09-07T020000-beta-info-one-deadbeef"
put alpha "2026-09-07T030000-beta-info-two-deadbeef"
set +e
out="$(lb alpha token deadbeef 2>&1)"
rc=$?
set -e
[[ $rc -ne 0 ]] || fail "ambiguous token rc=0"
echo "$out" | grep -q 'ambiguous-token' || fail "ambiguous message: $out"
echo "$out" | grep -q 'no dismiss, no ring' || fail "ambiguous missing fail-closed phrase: $out"
echo "$out" | grep -q CONFIDENTIAL && fail "ambiguous leaked body"
[[ -f "$box/alpha/inbox/2026-09-07T020000-beta-info-one-deadbeef.md" ]] || fail "ambiguous mutated letter"
[[ ! -s "$ringlog" ]] || fail "ambiguous rang doorbell"
pass "token ambiguous fail-closed (no ring, no mutation)"

put beta "2026-09-07T040000-beta-info-foreign-feedfeed"
set +e
fout="$(lb alpha token feedfeed 2>&1)"
frc=$?
set -e
if [[ "$plat" == "tmux" ]]; then
  [[ "$fout" == "unknown-token — no letter; ignore" ]] || fail "tmux own-mailbox leaked foreign: $fout"
  [[ $frc -eq 0 ]] || fail "tmux foreign rc=$frc"
  pass "tmux token own-mailbox (foreign is unknown)"
else
  echo "NOTE: $plat foreign-token output: $fout rc=$frc (peer scan; not rewritten this pass)"
fi

# --- empty send ---
set +e
sout="$(lb alpha send beta info empty-send </dev/null 2>&1)"
src=$?
set -e
[[ $src -ne 0 ]] || fail "empty send accepted"
echo "$sout" | grep -q 'empty message body' || fail "empty send missing refusal: $sout"
echo "$sout" | grep -q 'stdin' || fail "empty send missing stdin hint: $sout"
echo "$sout" | grep -q 'letterbox send' || fail "empty send missing usage: $sout"
if find "$box/beta/inbox" -name '*empty-send*' -print -quit | grep -q .; then
  fail "empty send published a letter"
fi
pass "empty send refuses with stdin hint (no publication)"

# --- empty reply ---
printf 'please do x\n' | lb beta send alpha request needs-reply --ack >/dev/null
shopt -s nullglob
req=("$box/alpha/inbox/"*needs-reply*.md)
shopt -u nullglob
[[ ${#req[@]} -eq 1 ]] || fail "setup request count ${#req[@]}"
req_id="$(awk -F': ' '$1 == "id" { print $2; exit }' "${req[0]}")"
set +e
rout="$(lb alpha reply "$req_id" ack empty-ack </dev/null 2>&1)"
rrc=$?
set -e
[[ $rrc -ne 0 ]] || fail "empty reply accepted"
echo "$rout" | grep -q 'empty reply body' || fail "empty reply missing refusal: $rout"
echo "$rout" | grep -q 'stdin' || fail "empty reply missing stdin hint: $rout"
echo "$rout" | grep -q 'letterbox reply' || fail "empty reply missing usage: $rout"
[[ -f "${req[0]}" ]] || fail "empty reply closed the letter"
if find "$box" -name '*.lifecycle.lock' -print -quit | grep -q .; then
  fail "empty reply left a lifecycle lock"
fi
if find "$box/beta/inbox" -name '*empty-ack*' -print -quit | grep -q .; then
  fail "empty reply published"
fi
pass "empty reply refuses with stdin hint (no closure, no lock)"

echo "cli-maintenance: PASS"
