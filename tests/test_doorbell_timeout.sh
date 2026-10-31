#!/usr/bin/env bash
# LETTERBOX_DOORBELL_TIMEOUT bounds each mux call: whole seconds 1-999, default
# 1. The bounded runner used to start the mux command before it read the bound,
# so a value such as "x" crashed it with the command already running and no
# limit. A bad value is now refused before any mux command.
set -euo pipefail

EDITION="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
work="$(mktemp -d /tmp/lb-timeout.XXXXXX)"
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

text_re=' send --surface '; enter_re=' send-key --surface .* Enter$'
line="📬 letterbox doorbell: unacked info in $work/box/agent/inbox/ — please check · 0a1b2c3d"

for v in '' 1 3 999; do
  out="$(adapter LETTERBOX_DOORBELL_ENTER_DELAY=0 ${v:+LETTERBOX_DOORBELL_TIMEOUT="$v"})"
  [[ "$out" == *"outcome=submitted"* ]] || bad "timeout '${v:-default}' still rings ($out)"
  # The call log, not just the outcome line: the doorbell typed once, exactly,
  # and one Enter.
  [[ "$(grep -cE "$text_re" "$MOCK_LOG")" == 1 && "$(grep -E "$text_re" "$MOCK_LOG")" == *" $line" ]] \
    || bad "timeout '${v:-default}' types the doorbell line once"
  [[ "$(grep -cE "$enter_re" "$MOCK_LOG")" == 1 ]] || bad "timeout '${v:-default}' presses Enter once"
done
ok "the default and whole seconds 1-999 ring as before"

for v in x 0 -1 1.5 1000 nan inf '1 '; do
  out="$(adapter LETTERBOX_DOORBELL_TIMEOUT="$v")"
  [[ "$out" == "doorbell-outcome v=1 outcome=no_live_surface reason=invalid_timeout target=-" ]] \
    || bad "invalid timeout '$v' is refused ($out)"
  [[ ! -s "$MOCK_LOG" ]] || bad "invalid timeout '$v' runs no cmux command"
done
ok "invalid timeouts are refused before any cmux command"

# Through the public `letterbox ring` too. Its own budget arithmetic must not
# trip on a value the adapter refuses: "08" is not octal, and a long value must
# not overflow.
ID="2026-10-31T170000-chat-bridge-info-q-0a1b2c3d"
printf -- '---\nid: %s\nfrom: chat-bridge\nto: agent\ntype: info\n---\nq\n' "$ID" > "$work/box/agent/inbox/$ID.md"
ring() { # [env assignments...]
  : > "$MOCK_LOG"
  env LETTERBOX_DIR="$work/box" PATH="$work/bin:$PATH" LETTERBOX_CMUX_SUBMIT=1 LETTERBOX_DOORBELL="$EDITION/adapters/cmux.sh" "$@" \
    "$EDITION/bin/letterbox" ring agent info "$ID" 2>"$work/ring.err"
}
for v in 08 099 9999999999999999999999999999999999999999; do
  out="$(ring LETTERBOX_DOORBELL_TIMEOUT="$v")"
  [[ "$out" == "doorbell-outcome v=1 outcome=no_live_surface reason=invalid_timeout target=-" ]] \
    || bad "ring refuses timeout '$v' ($out)"
  [[ ! -s "$work/ring.err" ]] || bad "ring with timeout '$v' prints no error ($(cat "$work/ring.err"))"
  [[ ! -s "$MOCK_LOG" ]] || bad "ring with timeout '$v' runs no cmux command"
done
out="$(ring LETTERBOX_DOORBELL_ENTER_DELAY=0)"
[[ "$out" == *"outcome=submitted"* ]] || bad "ring with the default timeout still rings ($out)"
ok "the public ring refuses them too, with no arithmetic error"

printf 'doorbell timeout suite: PASS (%s)\n' "$pass"
