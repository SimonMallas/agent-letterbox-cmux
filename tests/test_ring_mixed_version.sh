#!/usr/bin/env bash
# Mixed callers. helper_timeout means this process did not spend a lookup
# retry, so a released caller (three attempts, only that reason) may try
# again. lookup_spent means the wrapper already did, so that caller stops.
# A one-call caller loses recovery against a wrapper that still emits
# helper_timeout. tests/fixtures/letterbox-before-ring-retry is that
# wrapper, frozen from the 0.7.3 preview head. The working tree is the one
# under test. A committed candidate and a copy with no git history both
# use the frozen file.
set -euo pipefail

EDITION="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
work="$(mktemp -d "${TMPDIR:-/tmp}/lb-ring-mixed.XXXXXX")"
trap 'rm -rf "$work"' EXIT

mkdir -p "$work/box/agent/inbox" "$work/box/agent/processed" \
  "$work/box/tester/inbox" "$work/box/tester/processed" "$work/bin" "$work/old"
printf 'agent\tsurface:7\n' > "$work/box/cmux-agents.tsv"
mkdir -p "$work/old/bin"
cp "$EDITION/tests/fixtures/letterbox-before-ring-retry" "$work/old/bin/letterbox"
chmod +x "$work/old/bin/letterbox"
if grep -q 'lookup_spent' "$work/old/bin/letterbox"; then
  printf 'FAIL: frozen wrapper already emits lookup_spent, so it is not the old wrapper\n' >&2
  exit 1
fi

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
    printf '%s\n' 'doorbell-outcome v=1 outcome=submitted reason=- target=surface:7'
    ;;
  always)
    printf '%s\n' 'doorbell-outcome v=1 outcome=no_live_surface reason=helper_timeout target=-'
    ;;
  *) exit 9;;
esac
exit 0
FAKE
chmod +x "$work/bin/fake-ring.sh"

cat > "$work/caller.py" <<'PY'
import subprocess
import sys

binary = sys.argv[1]
attempts = int(sys.argv[2])
recipient, kind, letter_id = sys.argv[3], sys.argv[4], sys.argv[5]


def field(line, key):
    prefix = key + "="
    for part in line.split(" "):
        if part.startswith(prefix):
            return part[len(prefix):]
    return ""


last = ""
for attempt in range(attempts):
    proc = subprocess.run(
        [binary, "ring", recipient, kind, letter_id],
        capture_output=True, text=True)
    lines = [ln for ln in proc.stdout.splitlines() if ln.startswith("doorbell-outcome ")]
    if len(lines) != 1:
        print("BAD_LINES")
        sys.exit(2)
    line = lines[0]
    if field(line, "outcome") == "submitted" and proc.returncode == 0:
        print("OK")
        sys.exit(0)
    last = field(line, "reason")
    if last == "helper_timeout" and attempt + 1 < attempts:
        continue
    print("RingNotDelivered")
    print(last)
    sys.exit(1)
print("RingNotDelivered")
print(last)
sys.exit(1)
PY

pass=0
ok() { printf 'PASS: %s\n' "$1"; pass=$((pass + 1)); }
bad() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

# $1 name, $2 binary, $3 attempts, $4 mode, $5 calls, $6 result, $7 reason or -
case_n=0
run_case() {
  local name="$1" binary="$2" attempts="$3" mode="$4" want_calls="$5" want_result="$6" want_reason="$7"
  local id out calls reason
  case_n=$((case_n + 1))
  id="$(printf '2026-11-18T120100-tester-info-mix-%02d' "$case_n")"
  cat > "$work/box/agent/inbox/$id.md" <<EOF
---
id: $id
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
  rm -f "$work/ring.log"
  # A delivered failure exits 1. The assignment must not trip set -e.
  out="$(RING_MODE="$mode" RING_LOG="$work/ring.log" \
    LETTERBOX_DIR="$work/box" LETTERBOX_DOORBELL="$work/bin/fake-ring.sh" \
    LETTERBOX_DOORBELL_ENTER_DELAY=0 \
    python3 "$work/caller.py" "$binary" "$attempts" agent info "$id")" || true
  calls="$(cat "$work/ring.log")"
  reason="$(printf '%s\n' "$out" | awk 'NR==2 {print; exit}')"
  [[ "$calls" == "$want_calls" ]] || bad "$name calls=$calls want=$want_calls"
  [[ "$(printf '%s\n' "$out" | head -1)" == "$want_result" ]] || bad "$name result=$(printf '%s\n' "$out" | head -1)"
  if [[ "$want_reason" != "-" ]]; then
    [[ "$reason" == "$want_reason" ]] || bad "$name reason=$reason want=$want_reason"
  fi
  ok "$name"
}

new="$EDITION/bin/letterbox"
old="$work/old/bin/letterbox"
run_case "new wrapper + released caller recovers" "$new" 3 once 2 OK -
run_case "new wrapper + released caller stops at 3" "$new" 3 always 3 RingNotDelivered lookup_spent
run_case "new wrapper + one-call caller recovers" "$new" 1 once 2 OK -
run_case "new wrapper + one-call caller stops at 3" "$new" 1 always 3 RingNotDelivered lookup_spent
run_case "old wrapper + released caller recovers" "$old" 3 once 2 OK -
run_case "old wrapper + released caller exhausts at 3" "$old" 3 always 3 RingNotDelivered helper_timeout
run_case "old wrapper + one-call caller loses recovery" "$old" 1 once 1 RingNotDelivered helper_timeout
run_case "edition without retry + one-call caller is one lookup" "$old" 1 always 1 RingNotDelivered helper_timeout

printf 'MIXED: %s passed\n' "$pass"
