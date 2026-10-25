#!/usr/bin/env bash
# The doorbell's Enter waits LETTERBOX_DOORBELL_ENTER_DELAY seconds (default 2)
# after its text. An agent TUI that detects pastes swallowed an Enter sent with
# the text (Muse Code, 25 Oct). A bad value touches no terminal, and the ring
# wrapper's budget grows by the delay.
set -euo pipefail

EDITION="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
work="$(mktemp -d /tmp/lb-enter-delay.XXXXXX)"
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/bin" "$work/box/agent/inbox" "$work/box/agent/processed"

# Mock cmux: one live surface, and a timestamped log of every call.
cat > "$work/bin/cmux" <<'MOCK'
#!/usr/bin/env bash
printf '%s %s\n' "$(python3 -c 'import time; print(f"{time.time():.3f}")')" "$*" >> "$MOCK_LOG"
case "$1" in tree) echo 'surface:1 [terminal] "agent - pane"' ;; esac
exit 0
MOCK
chmod +x "$work/bin/cmux"
printf 'agent\tsurface:1\n' > "$work/box/cmux-agents.tsv"
export MOCK_LOG="$work/calls.log"

pass=0
ok() { printf 'PASS: %s\n' "$1"; pass=$((pass + 1)); }
bad() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }
adapter() { # [env assignments...]
  : > "$MOCK_LOG"
  env PATH="$work/bin:$PATH" LETTERBOX_DIR="$work/box" LETTERBOX_CMUX_SUBMIT=1 "$@" \
    "$EDITION/adapters/cmux.sh" agent info 0a1b2c3d
}
gap() { # seconds between the text step and the Enter step
  python3 - "$MOCK_LOG" <<'PY'
import sys
t = {}
for line in open(sys.argv[1]):
    stamp, cmd = line.split(" ", 1)
    if cmd.startswith("send-key "): t["enter"] = float(stamp)
    elif cmd.startswith("send "): t["text"] = float(stamp)
print(f"{t['enter'] - t['text']:.2f}")
PY
}

out="$(adapter)"
[[ "$out" == "doorbell-outcome v=1 outcome=submitted reason=- target=surface:1" ]] || bad "default ring submits ($out)"
g="$(gap)"; python3 -c "import sys; sys.exit(0 if $g >= 1.9 else 1)" || bad "default waits 2s before Enter (gap $g)"
[[ "$(grep -c '^[0-9.]* send-key ' "$MOCK_LOG")" == 1 ]] || bad "exactly one Enter"
ok "default: Enter follows the text after 2s ($g s), once"

out="$(adapter LETTERBOX_DOORBELL_ENTER_DELAY=0)"
g="$(gap)"; python3 -c "import sys; sys.exit(0 if $g < 1.0 else 1)" || bad "0 is the fast path (gap $g)"
ok "LETTERBOX_DOORBELL_ENTER_DELAY=0: no pause ($g s)"

for v in x 6 -1 1.5 '2 '; do
  out="$(adapter LETTERBOX_DOORBELL_ENTER_DELAY="$v")"
  [[ "$out" == "doorbell-outcome v=1 outcome=no_live_surface reason=invalid_enter_delay target=-" ]] \
    || bad "invalid delay '$v' is refused ($out)"
  [[ ! -s "$MOCK_LOG" ]] || bad "invalid delay '$v' runs no cmux command"
done
ok "invalid delays are refused before any cmux command"

# The ring wrapper's whole-run budget includes the pause: a fake adapter that
# takes 6s fits 4x0 + 5 + 2 = 7s, but not the old 4x0 + 5 = 5s.
ID="2026-10-25T170000-chat-bridge-info-q-0a1b2c3d"
printf -- '---\nid: %s\nfrom: chat-bridge\nto: agent\ntype: info\n---\nq\n' "$ID" > "$work/box/agent/inbox/$ID.md"
cat > "$work/slow-adapter.sh" <<'SLOW'
#!/usr/bin/env bash
sleep 6
echo 'doorbell-outcome v=1 outcome=submitted reason=- target=surface:1'
SLOW
chmod +x "$work/slow-adapter.sh"
out="$(env LETTERBOX_DIR="$work/box" LETTERBOX_DOORBELL="$work/slow-adapter.sh" LETTERBOX_DOORBELL_TIMEOUT=0 \
  "$EDITION/bin/letterbox" ring agent info "$ID")"
[[ "$out" == *"outcome=submitted"* ]] || bad "the ring budget covers the pause ($out)"
ok "ring budget grows by the Enter delay"

printf 'doorbell enter delay suite: PASS (%s)\n' "$pass"
