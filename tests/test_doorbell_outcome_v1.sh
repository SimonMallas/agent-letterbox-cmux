#!/usr/bin/env bash
# Release 2 W2 — cmux edition end-to-end: bin/letterbox send --now with a fake
# cmux and a real adapter. Everything faked inside this temp dir; no real cmux,
# no real letterbox, no credentials.
set -euo pipefail

EDITION="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
ROOT="$(mktemp -d /tmp/r2cmux-test.XXXXXX)"
trap 'rm -rf "$ROOT"' EXIT

mkdir -p "$ROOT/bin" "$ROOT/box/agent/inbox" "$ROOT/box/agent/processed" \
         "$ROOT/box/tester/inbox" "$ROOT/box/tester/processed"
printf 'agent\tsurface:7\n' > "$ROOT/box/cmux-agents.tsv"
export BOX="$ROOT/box" LETTERBOX_DIR="$ROOT/box" LETTERBOX_AGENT=tester
export LETTERBOX_DOORBELL_TIMEOUT=3

# Fake cmux (behavior by env) -------------------------------------------------
cat > "$ROOT/bin/cmux" <<'CMUX'
#!/usr/bin/env bash
set -euo pipefail
log="${CMUX_FAKE_LOG:?}"
printf '%s\n' "$*" >> "$log"
if [[ "$*" == *"tree --all"* ]]; then
  case "${CMUX_FAKE_TREE:-ok}" in
    ok)    printf '{"windows":[{"id":"w1","workspaces":[{"id":"ws1","panes":[{"id":"pane:1","surface":"surface:7"}]}]}]}\n';;
    sleep) sleep "${CMUX_FAKE_SLEEP:-5}";;
    exit124) exit 124;;
  esac
  exit 0
fi
case "${1:-}" in
  send)     case "${CMUX_FAKE_SEND:-ok}" in
              ok) exit 0;; fail) exit 1;; sleep) sleep "${CMUX_FAKE_SLEEP:-5}";; exit124) exit 124;;
            esac;;
  send-key) case "${CMUX_FAKE_ENTER:-ok}" in
              ok) exit 0;; fail) exit 1;; sleep) sleep "${CMUX_FAKE_SLEEP:-5}";;
            esac;;
  notify)   case "${CMUX_FAKE_NOTIFY:-ok}" in
              ok) :;; sleep) sleep "${CMUX_FAKE_SLEEP:-5}";;
            esac;;
esac
exit 0
CMUX
chmod +x "$ROOT/bin/cmux"
export PATH="$ROOT/bin:$PATH"
export CMUX_FAKE_LOG="$ROOT/cmux.log"
export LETTERBOX_DOORBELL="$EDITION/adapters/cmux.sh"
export LETTERBOX_CMUX_SUBMIT="${LETTERBOX_CMUX_SUBMIT:-1}"

# Misbehaving doorbells for wrapper classifier edge cases.
cat > "$ROOT/garbage.sh" <<'SH'
#!/usr/bin/env bash
echo 'not a contract line'
SH
cat > "$ROOT/double.sh" <<'SH'
#!/usr/bin/env bash
echo 'doorbell-outcome v=1 outcome=submitted reason=- target=surface:7'
echo 'doorbell-outcome v=1 outcome=submitted reason=- target=surface:7'
SH
cat > "$ROOT/valid-exit1.sh" <<'SH'
#!/usr/bin/env bash
echo 'doorbell-outcome v=1 outcome=submitted reason=- target=surface:7'
exit 1
SH
cat > "$ROOT/line-hang.sh" <<'SH'
#!/usr/bin/env bash
echo 'doorbell-outcome v=1 outcome=submitted reason=- target=surface:7'
sleep 30
SH
chmod +x "$ROOT/garbage.sh" "$ROOT/double.sh" "$ROOT/valid-exit1.sh" "$ROOT/line-hang.sh"

# PATH farm WITH the fake cmux but WITHOUT python3: a missing runner must be
# adapter_unavailable (non-retryable), never helper_timeout.
mkdir -p "$ROOT/bin-nopython"
for t in bash grep awk sed shasum od tr date mktemp ln rm cat \
         dirname basename env sleep; do
  src="$(command -v "$t" 2>/dev/null || true)"
  [[ -n "$src" ]] && ln -sf "$src" "$ROOT/bin-nopython/$t"
done
ln -sf "$ROOT/bin/cmux" "$ROOT/bin-nopython/cmux"

send_now() { # $1.. = env overrides
  env BOX="$BOX" LETTERBOX_AGENT=tester LETTERBOX_DIR="$BOX" \
    LETTERBOX_DOORBELL="$LETTERBOX_DOORBELL" LETTERBOX_CMUX_SUBMIT="$LETTERBOX_CMUX_SUBMIT" \
    LETTERBOX_DOORBELL_TIMEOUT="$LETTERBOX_DOORBELL_TIMEOUT" \
    PATH="$PATH" CMUX_FAKE_LOG="$CMUX_FAKE_LOG" "$@" \
    bash -c 'printf "test body\n" | "$0" send agent info testslug --now' "$EDITION/bin/letterbox" 2>/dev/null
}

one_line() {
  local out="$1" n
  n="$(printf '%s\n' "$out" | grep -c '^doorbell-outcome ' || true)"
  [[ "$n" == "1" ]] || { echo "SOLE-EMISSION FAIL ($n lines): $out"; exit 1; }
}

craft_letter() { # $1=from $2=id — hand-write a durable letter into agent's inbox
  cat > "$BOX/agent/inbox/$2.md" <<EOF
---
id: $2
from: $1
to: agent
type: info
re:
priority: later
requires_ack: false
deadline:
---
crafted body
EOF
}

nudge() { # $1=id — re-ring an existing letter through the full wrapper path
  env BOX="$BOX" LETTERBOX_AGENT=tester LETTERBOX_DIR="$BOX" \
    LETTERBOX_DOORBELL="$LETTERBOX_DOORBELL" LETTERBOX_CMUX_SUBMIT=1 \
    LETTERBOX_DOORBELL_TIMEOUT="$LETTERBOX_DOORBELL_TIMEOUT" \
    PATH="$PATH" CMUX_FAKE_LOG="$CMUX_FAKE_LOG" \
    "$EDITION/bin/letterbox" nudge "$1" 2>/dev/null
}

pass=0
check() { # $1=name $2=env-string $3=expected
  local name="$1" envs="$2" expected="$3" out
  out="$(send_now $envs)"
  one_line "$out"
  out="$(printf '%s\n' "$out" | grep '^doorbell-outcome ')"
  if [[ "$out" == "$expected" ]]; then
    echo "PASS: $name"; pass=$((pass+1))
  else
    echo "FAIL: $name"; echo "  expected: $expected"; echo "  got:      $out"; exit 1
  fi
}

check "submitted (two-step ok)"        "CMUX_FAKE_TREE=ok CMUX_FAKE_SEND=ok CMUX_FAKE_ENTER=ok" \
  'doorbell-outcome v=1 outcome=submitted reason=- target=surface:7'
check "lookup timeout → helper_timeout" "CMUX_FAKE_TREE=sleep CMUX_FAKE_SLEEP=5" \
  'doorbell-outcome v=1 outcome=no_live_surface reason=helper_timeout target=-'
check "send reported fail → send_failed" "CMUX_FAKE_SEND=fail" \
  'doorbell-outcome v=1 outcome=no_live_surface reason=send_failed target=-'
check "send timeout → unconfirmed"      "CMUX_FAKE_SEND=sleep CMUX_FAKE_SLEEP=5" \
  'doorbell-outcome v=1 outcome=no_live_surface reason=unconfirmed target=-'
check "enter reported fail → pasted"    "CMUX_FAKE_ENTER=fail" \
  'doorbell-outcome v=1 outcome=pasted_not_submitted reason=enter_failed target=surface:7'
check "enter timeout → unconfirmed"     "CMUX_FAKE_ENTER=sleep CMUX_FAKE_SLEEP=5" \
  'doorbell-outcome v=1 outcome=no_live_surface reason=unconfirmed target=-'
check "notify-only (SUBMIT=0)"          "LETTERBOX_CMUX_SUBMIT=0" \
  'doorbell-outcome v=1 outcome=no_live_surface reason=notify_only target=-'
check "missing python3 → adapter_unavailable (not helper_timeout)" "PATH=$ROOT/bin-nopython" \
  'doorbell-outcome v=1 outcome=no_live_surface reason=adapter_unavailable target=-'
check "wrapper: garbage child → unconfirmed" "LETTERBOX_DOORBELL=$ROOT/garbage.sh" \
  'doorbell-outcome v=1 outcome=no_live_surface reason=unconfirmed target=-'
check "wrapper: double line → unconfirmed" "LETTERBOX_DOORBELL=$ROOT/double.sh" \
  'doorbell-outcome v=1 outcome=no_live_surface reason=unconfirmed target=-'
# Exit-status precedence: a valid line after a NONZERO exit is never forwarded.
check "wrapper: valid line + nonzero exit → unconfirmed" "LETTERBOX_DOORBELL=$ROOT/valid-exit1.sh" \
  'doorbell-outcome v=1 outcome=no_live_surface reason=unconfirmed target=-'
# Runner-owned sentinel: a child exiting 124 on its own is NOT a timeout.
check "child exit 124 in lookup → surface_not_found (not helper_timeout)" "CMUX_FAKE_TREE=exit124" \
  'doorbell-outcome v=1 outcome=no_live_surface reason=surface_not_found target=-'
check "child exit 124 in send → send_failed (not unconfirmed)" "CMUX_FAKE_SEND=exit124" \
  'doorbell-outcome v=1 outcome=no_live_surface reason=send_failed target=-'
# A success line followed by a hang: the wrapper backstop kills, line or not.
check "wrapper: valid line then hang → unconfirmed" "LETTERBOX_DOORBELL=$ROOT/line-hang.sh LETTERBOX_DOORBELL_TIMEOUT=1" \
  'doorbell-outcome v=1 outcome=no_live_surface reason=unconfirmed target=-'
# Bounded notify: a hung notify never holds the inject path hostage.
check "hung notify still submits" "CMUX_FAKE_NOTIFY=sleep CMUX_FAKE_SLEEP=5" \
  'doorbell-outcome v=1 outcome=submitted reason=- target=surface:7'

# Ruling 5 provenance: the from clause names the durable letter's sender,
# never the calling process identity (ME=tester, letter from relaybot).
craft_letter relaybot 2026-09-16T000000-relaybot-info-crafted-a1b2c3d4
out="$(nudge 2026-09-16T000000-relaybot-info-crafted-a1b2c3d4)"
one_line "$out"
out="$(printf '%s\n' "$out" | grep '^doorbell-outcome ')"
if [[ "$out" == 'doorbell-outcome v=1 outcome=submitted reason=- target=surface:7' ]] \
  && grep -q 'unacked info from relaybot in ' "$CMUX_FAKE_LOG"; then
  echo "PASS: from clause names the letter's sender, not ME"; pass=$((pass+1))
else
  echo "FAIL: from clause names the letter's sender, not ME"; echo "$out"; cat "$CMUX_FAKE_LOG"; exit 1
fi

# Ruling 5 safety: an invalid sender value omits the clause (never "from -").
craft_letter 'bad/../x' 2026-09-16T000001-badsend-info-crafted-b2c3d4e5
: > "$CMUX_FAKE_LOG"
out="$(nudge 2026-09-16T000001-badsend-info-crafted-b2c3d4e5)"
one_line "$out"
out="$(printf '%s\n' "$out" | grep '^doorbell-outcome ')"
if [[ "$out" == 'doorbell-outcome v=1 outcome=submitted reason=- target=surface:7' ]] \
  && ! grep -q ' from ' "$CMUX_FAKE_LOG" \
  && grep -q 'unacked info in ' "$CMUX_FAKE_LOG"; then
  echo "PASS: invalid sender omits the from clause"; pass=$((pass+1))
else
  echo "FAIL: invalid sender omits the from clause"; echo "$out"; cat "$CMUX_FAKE_LOG"; exit 1
fi

echo "──"
echo "cmux edition e2e: $pass/17 PASS"
