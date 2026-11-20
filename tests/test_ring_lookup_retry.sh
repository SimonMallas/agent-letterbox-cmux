#!/usr/bin/env bash
# Lookup retry lives in the ring wrapper. One pre-injection helper_timeout
# then a success rings once. Three timeouts leave a record, a visible
# failure, and no ring. A timeout after injection starts is not retried.
set -euo pipefail

EDITION="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
work="$(mktemp -d "${TMPDIR:-/tmp}/lb-ring-retry.XXXXXX")"
trap 'rm -rf "$work"' EXIT

mkdir -p "$work/box/agent/inbox" "$work/box/agent/processed" \
  "$work/box/tester/inbox" "$work/box/tester/processed" "$work/bin"
printf 'agent\tsurface:7\n' > "$work/box/cmux-agents.tsv"

cat > "$work/bin/fake-ring.sh" <<'FAKE'
#!/usr/bin/env bash
log="${RING_LOG:?}"
n=0
[[ -f "$log" ]] && n="$(cat "$log")"
n=$((n + 1))
printf '%s\n' "$n" > "$log"
case "${RING_MODE:?}" in
  once)
    if [[ "$n" -eq 1 ]]; then
      printf '%s\n' 'doorbell-outcome v=1 outcome=no_live_surface reason=helper_timeout target=-'
      exit 0
    fi
    printf 'RING\n' >> "${RING_HITS:?}"
    printf '%s\n' 'doorbell-outcome v=1 outcome=submitted reason=- target=surface:7'
    ;;
  always)
    printf '%s\n' 'doorbell-outcome v=1 outcome=no_live_surface reason=helper_timeout target=-'
    ;;
  late)
    printf '%s\n' 'doorbell-outcome v=1 outcome=no_live_surface reason=unconfirmed target=-'
    ;;
  missing)
    printf '%s\n' 'doorbell-outcome v=1 outcome=no_live_surface reason=surface_not_found target=-'
    ;;
  *) exit 9;;
esac
exit 0
FAKE

cat > "$work/bin/cmux" <<'CMUX'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${MOCK_LOG:?}"
if [[ "$*" == *tree\ --all* ]]; then
  sleep "${TREE_SLEEP:?}"
  printf '%s\n' 'surface:7'
fi
exit 0
CMUX
chmod +x "$work/bin/fake-ring.sh" "$work/bin/cmux"

pass=0
ok() { printf 'PASS: %s\n' "$1"; pass=$((pass + 1)); }
bad() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

craft() { # $1=id
  cat > "$work/box/agent/inbox/$1.md" <<EOF
---
id: $1
from: tester
to: agent
type: info
re:
priority: later
requires_ack: false
deadline:
---
body
EOF
}

one_line() { # $1=stdout $2=expected outcome fragment
  local n
  n="$(printf '%s\n' "$1" | grep -c '^doorbell-outcome ' || true)"
  [[ "$n" == 1 ]] || bad "expected one outcome line, got ${n:-0}"
  printf '%s\n' "$1" | grep -q "$2" || bad "outcome was not $2"
}

ring_fake() { # $1=id $2=mode
  rm -f "$work/ring.log" "$work/hits.log" "$work/out" "$work/err"
  RING_MODE="$2" RING_LOG="$work/ring.log" RING_HITS="$work/hits.log" \
    LETTERBOX_DIR="$work/box" LETTERBOX_DOORBELL="$work/bin/fake-ring.sh" \
    LETTERBOX_DOORBELL_ENTER_DELAY=0 \
    "$EDITION/bin/letterbox" ring agent info "$1" >"$work/out" 2>"$work/err"
}

ID_ONCE="2026-11-18T120001-tester-info-once-a0000001"
ID_EXHAUST="2026-11-18T120002-tester-info-exhaust-a0000002"
ID_LATE="2026-11-18T120003-tester-info-late-a0000003"
ID_MISS="2026-11-18T120004-tester-info-miss-a0000004"
ID_CAP="2026-11-18T120005-tester-info-cap-a0000005"
ID_REAL="2026-11-18T120006-tester-info-real3-a0000006"
craft "$ID_ONCE"
craft "$ID_EXHAUST"
craft "$ID_LATE"
craft "$ID_MISS"
craft "$ID_CAP"
craft "$ID_REAL"

ring_fake "$ID_ONCE" once
one_line "$(cat "$work/out")" 'outcome=submitted '
[[ "$(cat "$work/ring.log")" == 2 ]] || bad "one timeout then success did not look up twice"
[[ "$(grep -c '^RING$' "$work/hits.log")" == 1 ]] || bad "one timeout then success did not ring exactly once"
[[ ! -s "$work/err" ]] || bad "a recovered lookup printed a failure"
[[ ! -e "$work/box/.unresolved-rings/agent/$ID_ONCE" ]] || bad "a recovered lookup left a record"
ok "one timeout then success rings exactly once"

ring_fake "$ID_EXHAUST" always
one_line "$(cat "$work/out")" 'reason=lookup_spent '
[[ "$(cat "$work/ring.log")" == 3 ]] || bad "exhaustion did not look up three times"
[[ ! -e "$work/hits.log" ]] || bad "exhaustion rang"
grep -q 'nudge to retry' "$work/err" || bad "exhaustion did not tell the sender to nudge"
if grep -E '/(Users|home)/' "$work/err" >/dev/null; then
  bad "the failure line contains a home path"
fi
rec="$work/box/.unresolved-rings/agent/$ID_EXHAUST"
[[ -f "$rec" ]] || bad "exhaustion wrote no record"
grep -q "^letter: $ID_EXHAUST$" "$rec" || bad "record letter key"
grep -q '^to: agent$' "$rec" || bad "record recipient key"
grep -q '^reason: helper_timeout$' "$rec" || bad "record reason"
grep -q '^attempts: 3$' "$rec" || bad "record attempts"
check_out="$(LETTERBOX_DIR="$work/box" LETTERBOX_AGENT=tester \
  "$EDITION/bin/letterbox" check agent)"
printf '%s\n' "$check_out" | grep -q 'ring unresolved: .*a0000002: lookup timed out before any text; nudge to retry' \
  || bad "check does not show the unresolved ring"
ok "three timeouts give the record, the visible failure, and no ring"

# Filing is not a ring. The warning must stop, and the record must go.
rings_before="$(cat "$work/ring.log")"
file_out="$(LETTERBOX_DIR="$work/box" LETTERBOX_AGENT=agent \
  "$EDITION/bin/letterbox" file "$ID_EXHAUST" 2>"$work/file.err")"
printf '%s\n' "$file_out" | grep -q '^filed:' || bad "file did not file the exhausted letter"
[[ ! -s "$work/file.err" ]] || bad "file printed a failure"
[[ "$(cat "$work/ring.log")" == "$rings_before" ]] || bad "filing the letter rang"
if printf '%s\n' "$file_out" | grep -q 'doorbell-outcome '; then
  bad "filing the letter emitted an outcome"
fi
check_out="$(LETTERBOX_DIR="$work/box" LETTERBOX_AGENT=tester \
  "$EDITION/bin/letterbox" check agent)"
if printf '%s\n' "$check_out" | grep -q 'ring unresolved: .*a0000002:'; then
  bad "check still names a ring after the letter was filed"
fi
[[ ! -e "$work/box/.unresolved-rings/agent/$ID_EXHAUST" ]] || bad "the record survived filing"
ok "filing the letter drops the unresolved ring and does not ring"

# Any other departure has the same end. check must not keep the warning.
ID_GONE="2026-11-18T120007-tester-info-gone-a0000007"
craft "$ID_GONE"
printf 'letter: %s\nto: agent\nreason: helper_timeout\nattempts: 3\n' "$ID_GONE" \
  > "$work/box/.unresolved-rings/agent/$ID_GONE"
mv "$work/box/agent/inbox/$ID_GONE.md" "$work/box/agent/processed/"
check_out="$(LETTERBOX_DIR="$work/box" LETTERBOX_AGENT=tester \
  "$EDITION/bin/letterbox" check agent)"
if printf '%s\n' "$check_out" | grep -q 'a0000007'; then
  bad "check names a ring whose letter has left the inbox"
fi
[[ ! -e "$work/box/.unresolved-rings/agent/$ID_GONE" ]] || bad "check left a record whose letter has left the inbox"
ok "a record whose letter has left the inbox is dropped"

# A stale record must not survive a ring that is not an exhausted lookup.
mkdir -p "$work/box/.unresolved-rings/agent"
printf 'letter: %s\nto: agent\nreason: helper_timeout\nattempts: 3\n' "$ID_LATE" \
  > "$work/box/.unresolved-rings/agent/$ID_LATE"
ring_fake "$ID_LATE" late
one_line "$(cat "$work/out")" 'reason=unconfirmed '
[[ "$(cat "$work/ring.log")" == 1 ]] || bad "a post-injection timeout was retried"
[[ ! -s "$work/err" ]] || bad "an unconfirmed ring printed a lookup failure"
[[ ! -e "$work/box/.unresolved-rings/agent/$ID_LATE" ]] || bad "an unconfirmed ring left the record"
ok "a post-injection timeout is not retried"

ring_fake "$ID_MISS" missing
one_line "$(cat "$work/out")" 'reason=surface_not_found '
[[ "$(cat "$work/ring.log")" == 1 ]] || bad "surface_not_found was retried"
[[ ! -s "$work/err" ]] || bad "surface_not_found printed a lookup failure"
ok "a lookup that finds nobody is not retried"

# A directory slot that is a regular file cannot hold the record. Do not
# claim the nudge path, and do not print the temp path.
ID_BLOCK="2026-11-18T120008-tester-info-block-a0000008"
craft "$ID_BLOCK"
rm -rf "$work/box/.unresolved-rings"
printf 'blocked\n' > "$work/box/.unresolved-rings"
ring_fake "$ID_BLOCK" always
one_line "$(cat "$work/out")" 'reason=lookup_spent '
[[ "$(cat "$work/ring.log")" == 3 ]] || bad "a blocked record path changed the lookup count"
if grep -F "$work" "$work/err" >/dev/null; then
  bad "a failed record write printed a path"
fi
if grep -E '/(Users|home)/' "$work/err" >/dev/null; then
  bad "a failed record write printed a home path"
fi
if grep -q 'nudge to retry' "$work/err"; then
  bad "a failed record write still told the sender to nudge"
fi
grep -q 'record was not written' "$work/err" || bad "a failed record write was silent"
[[ -f "$work/box/.unresolved-rings" && ! -d "$work/box/.unresolved-rings" ]] \
  || bad "the blocking file was replaced"
rm -f "$work/box/.unresolved-rings"
ok "a blocked record path does not claim the record or print a path"

# Real adapter, default step cap. 1.5s used to be helper_timeout at the 1s cap.
rm -f "$work/mock.log" "$work/out" "$work/err"
TREE_SLEEP=1.5 MOCK_LOG="$work/mock.log" \
  PATH="$work/bin:$PATH" LETTERBOX_DIR="$work/box" \
  LETTERBOX_DOORBELL="$EDITION/adapters/cmux.sh" LETTERBOX_DOORBELL_ENTER_DELAY=0 \
  "$EDITION/bin/letterbox" ring agent info "$ID_CAP" >"$work/out" 2>"$work/err"
one_line "$(cat "$work/out")" 'outcome=submitted '
trees="$(grep -c 'tree --all' "$work/mock.log" || true)"
sends="$(grep -c 'send --surface' "$work/mock.log" || true)"
[[ "$trees" == 1 ]] || bad "a 1.5s lookup was not one try under the 2s cap"
[[ "$sends" == 1 ]] || bad "a 1.5s lookup did not ring once"
[[ ! -s "$work/err" ]] || bad "a lookup inside the cap printed a failure"
ok "a lookup between 1s and 2s rings once"

rm -f "$work/mock.log" "$work/out" "$work/err"
TREE_SLEEP=3 MOCK_LOG="$work/mock.log" \
  PATH="$work/bin:$PATH" LETTERBOX_DIR="$work/box" \
  LETTERBOX_DOORBELL="$EDITION/adapters/cmux.sh" LETTERBOX_DOORBELL_ENTER_DELAY=0 \
  "$EDITION/bin/letterbox" ring agent info "$ID_REAL" >"$work/out" 2>"$work/err"
one_line "$(cat "$work/out")" 'reason=lookup_spent '
trees="$(grep -c 'tree --all' "$work/mock.log" || true)"
sends="$(grep -c 'send --surface' "$work/mock.log" || true)"
[[ "$trees" == 3 ]] || bad "a 3s lookup was not tried three times (got ${trees:-0})"
[[ "$sends" == 0 ]] || bad "a timed-out lookup rang"
[[ -f "$work/box/.unresolved-rings/agent/$ID_REAL" ]] || bad "the real adapter exhaustion wrote no record"
grep -q 'nudge to retry' "$work/err" || bad "the real adapter exhaustion did not tell the sender to nudge"
ok "three real lookup timeouts give the record and no ring"

printf 'ring lookup retry: PASS (%s)\n' "$pass"
