#!/usr/bin/env bash
# Public-safe v0.3 core: short path, file C, resolver, doorbell, check, privacy.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
letterbox="$root/bin/letterbox"
fails=0
pass() { printf 'PASS: %s\n' "$*"; }
fail() { printf 'FAIL: %s\n' "$*" >&2; fails=$((fails + 1)); }

CANARY="canaryslugxyz-leaky-task"
box=""
cleanup() { [[ -n "${box:-}" && -d "$box" ]] && rm -rf "$box"; return 0; }
trap cleanup EXIT
new_box() {
  cleanup
  box="$(mktemp -d "${TMPDIR:-/tmp}/lb-v03.XXXXXX")"
  LETTERBOX_DIR="$box" "$letterbox" init planner reviewer >/dev/null
}
lb() {
  local agent="$1"; shift
  LETTERBOX_DIR="$box" LETTERBOX_AGENT="$agent" "$letterbox" "$@"
}
write_letter() { # to from type req id
  cat > "$box/$1/inbox/${5}.md" <<EOF
---
id: $5
from: $2
to: $1
type: $3
re:
priority: now
requires_ack: $4
deadline:
---
body $CANARY for $5
EOF
}

# ── no-ACK short path ──
new_box
write_letter reviewer planner request false "2026-08-16T080000-planner-request-small-aaaa1111"
if printf 'done\n' | lb reviewer reply 2026-08-16T080000-planner-request-small-aaaa1111 result small-done; then
  [[ -f "$box/reviewer/processed/2026-08-16T080000-planner-request-small-aaaa1111.md" ]] && pass "A1 one-shot result on requires_ack:false" || fail "A1 missing archive"
else
  fail "A1 reply result failed"
fi
write_letter reviewer planner request false "2026-08-16T080001-planner-request-noack-bbbb2222"
if printf 'nope\n' | lb reviewer reply 2026-08-16T080001-planner-request-noack-bbbb2222 ack taking 2>/dev/null; then
  fail "A1 ack on non-task should fail"
else
  pass "A1 ack refused on non-task"
fi

# ── structural file C ──
new_box
write_letter reviewer planner result false "2026-08-16T080002-planner-result-peer-dddd4444"
if lb reviewer file "$box/reviewer/inbox/2026-08-16T080002-planner-result-peer-dddd4444.md" 2>/dev/null; then
  fail "C path RESULT without --read"
else
  pass "C path RESULT refused without --read"
fi
lb reviewer file "$box/reviewer/inbox/2026-08-16T080002-planner-result-peer-dddd4444.md" --read
[[ -f "$box/reviewer/processed/2026-08-16T080002-planner-result-peer-dddd4444.md" ]] && pass "C path RESULT files with --read" || fail "C --read"
write_letter reviewer planner result false "2026-08-16T080003-planner-result-byid-dddd4445"
lb reviewer file 2026-08-16T080003-planner-result-byid-dddd4445
[[ -f "$box/reviewer/processed/2026-08-16T080003-planner-result-byid-dddd4445.md" ]] && pass "C explicit ID RESULT files without --read" || fail "C id file"

# ── display/token resolver + privacy ──
new_box
LID="2026-08-16T080100-planner-info-${CANARY}-abcd1234"
DISP="2026-08-16T080100 · abcd1234"
write_letter reviewer planner info false "$LID"
out="$(lb reviewer read "$DISP")"
echo "$out" | grep -q "^id: $LID$" && pass "read display_id" || fail "read display"
echo "$out" | grep -q "$CANARY" || fail "read should show body"
if lb reviewer read "$box/reviewer/inbox/${LID}.md" 2>/dev/null; then fail "read accepted path"; else pass "read rejects path"; fi
fout="$(lb reviewer file "$DISP")"
[[ "$fout" == "filed: $DISP → reviewer/processed/" ]] && pass "file confirmation display_id" || fail "file confirm: $fout"
echo "$fout" | grep -q "$CANARY" && fail "file confirm leaked canary" || pass "file confirm no canary"

# ── progress + check ──
new_box
LIVE="2026-08-16T080200-planner-request-${CANARY}-abcd1234"
write_letter reviewer planner request true "$LIVE"
printf 'ack_id: a\nacked_at: 2026-08-16T08:02:00Z\nby: reviewer\n' > "$box/reviewer/inbox/${LIVE}.md.ack"
pout="$(lb reviewer progress "$LIVE" "still mapping")"
[[ "$pout" == "progress: 2026-08-16T080200 · abcd1234" ]] && pass "progress display_id" || fail "progress: $pout"
echo "$pout" | grep -q "$CANARY" && fail "progress leaked canary"
chk="$(lb reviewer check)"
echo "$chk" | grep -q 'progress: still mapping' && pass "default check shows progress" || fail "check progress"
echo "$chk" | grep -q "$CANARY" && fail "check leaked canary" || pass "check no canary/slug"
echo "$chk" | grep -q '2026-08-16T080200 · abcd1234' && pass "check emits display_id" || fail "check display"
echo "$chk" | grep -q '\[ACCEPTED\]' && pass "check keeps ACCEPTED" || fail "check accepted"

# ── stale / recent ──
STALE="2026-07-01T080000-planner-request-${CANARY}-eeee5555"
write_letter reviewer planner request true "$STALE"
chk="$(lb reviewer check)"
echo "$chk" | grep -q STALE && pass "old letter marked STALE" || fail "stale mark"
rec="$(lb reviewer check --recent)"
echo "$rec" | grep -q 'stale items hidden' && pass "--recent hidden-count footer" || fail "recent footer"
echo "$rec" | grep -q 'eeee5555' && fail "--recent showed stale display" || true

# ── doorbell token / nudge (no slug) ──
new_box
export LETTERBOX_DOORBELL="$box/doorbell.sh"
cat > "$LETTERBOX_DOORBELL" <<'EOF'
#!/bin/bash
echo "RING $1 $2 $3" >> "${DOORBELL_LOG:-/tmp/lb-ring.log}"
EOF
chmod +x "$LETTERBOX_DOORBELL"
export DOORBELL_LOG="$box/ring.log"
: > "$DOORBELL_LOG"
printf 'hello %s\n' "$CANARY" | lb planner send reviewer request "$CANARY" --now --ack
if grep -q "$CANARY" "$DOORBELL_LOG"; then fail "doorbell leaked canary"; else pass "doorbell token has no canary"; fi
grep -qE 'RING reviewer request [0-9a-f]{8}' "$DOORBELL_LOG" && pass "doorbell uses 8-hex token" || fail "doorbell log: $(cat "$DOORBELL_LOG")"
LID="$(basename "$(ls "$box/reviewer/inbox/"*.md | head -1)" .md)"
: > "$DOORBELL_LOG"
lb planner nudge "$LID" >/dev/null
grep -q 'RING reviewer' "$DOORBELL_LOG" && pass "nudge re-rings open letter" || fail "nudge no ring"
INFO="2026-08-16T080300-planner-info-nudgefile-ffff6666"
write_letter reviewer planner info false "$INFO"
lb reviewer file "$INFO" >/dev/null
if lb planner nudge "$INFO" 2>/dev/null; then
  fail "nudge on filed should refuse"
else
  pass "nudge refuses filed/terminal"
fi

# ── token collision ──
new_box
write_letter reviewer planner info false "2026-08-16T081000-planner-info-one-deadbeef"
write_letter reviewer planner info false "2026-08-01T090000-planner-info-two-deadbeef"
set +e
coll="$(lb reviewer read deadbeef 2>&1)"
cec=$?
set -e
[[ $cec -ne 0 ]] && echo "$coll" | grep -q 'ambiguous' && pass "token collision refuses" || fail "collision: $coll"

# ── thread read-only ──
new_box
THR="2026-08-16T081100-planner-request-thread-1111aaaa"
write_letter reviewer planner request true "$THR" 
# add thread field
# rewrite with thread
python3 - "$box/reviewer/inbox/${THR}.md" "$THR" <<'PY'
from pathlib import Path
import sys
p = Path(sys.argv[1]); th = sys.argv[2]
t = p.read_text().replace("re:\n", f"re:\nthread: {th}\n", 1)
p.write_text(t)
PY
before=$(find "$box" -type f | sort | cksum)
tout="$(lb planner check --thread "$THR")"
after=$(find "$box" -type f | sort | cksum)
[[ "$before" == "$after" ]] && pass "--thread writes zero files" || fail "thread wrote"
echo "$tout" | grep -q "$CANARY" && fail "thread leaked canary" || pass "thread no canary"

if (( fails > 0 )); then
  printf 'lifecycle-v03: FAIL (%d)\n' "$fails" >&2
  exit 1
fi
printf 'lifecycle-v03: PASS\n'
