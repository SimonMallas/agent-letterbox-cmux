#!/usr/bin/env bash
# Mock-backed proof that adapters/cmux.sh types the doorbell into the resolved
# pane by default, and that only LETTERBOX_CMUX_SUBMIT=0 stops it.
set -euo pipefail
unset LETTERBOX_CMUX_SUBMIT # each case below sets it on purpose; an inherited value must not decide one

root="$(cd "$(dirname "$0")/.." && pwd)"
adapter="$root/adapters/cmux.sh"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# Mock `cmux`: logs every invocation, and answers `tree --all` with a fake
# pane so the adapter's surface lookup succeeds and reaches the
# LETTERBOX_CMUX_SUBMIT gate instead of deferring earlier for an unrelated
# reason (no live surface, cmux missing, etc).
mockbin="$work/bin"
mkdir -p "$mockbin"
cat > "$mockbin/cmux" <<'MOCK'
#!/usr/bin/env bash
echo "$*" >> "$MOCK_LOG"
case "$1" in
  tree) echo 'surface:1 [terminal] "reviewer - pane"' ;;
  *) : ;;
esac
exit 0
MOCK
chmod +x "$mockbin/cmux"

patterns="$work/cmux-patterns.tsv"
printf 'reviewer\treviewer\n' > "$patterns"

MOCK_LOG="$work/cmux-calls.log"
export MOCK_LOG

run_adapter() {
  : > "$MOCK_LOG"
  PATH="$mockbin:$PATH" \
    LETTERBOX_DIR="$work/box" \
    LETTERBOX_CMUX_PATTERNS="$patterns" \
    MOCK_LOG="$MOCK_LOG" \
    "$adapter" reviewer delegate smoke-test
}

# --- Default (LETTERBOX_CMUX_SUBMIT unset): the doorbell is typed and submitted ---
unset LETTERBOX_CMUX_SUBMIT || true
run_adapter
grep -qE '^send --surface ' "$work/cmux-calls.log" && grep -qE '^send-key --surface .* Enter$' "$work/cmux-calls.log" || {
  echo 'FAIL: the default did not type and submit the doorbell' >&2
  cat "$work/cmux-calls.log" >&2
  exit 1
}
grep -q '^notify ' "$work/cmux-calls.log" || {
  echo 'FAIL: expected the OS notification to fire as well' >&2
  exit 1
}
echo 'PASS: the doorbell is typed by default'

# --- LETTERBOX_CMUX_SUBMIT=0: the only way to stop typing ---
LETTERBOX_CMUX_SUBMIT=0 run_adapter
if grep -qE '^(send|send-key) ' "$work/cmux-calls.log"; then
  echo 'FAIL: cmux send/send-key called with LETTERBOX_CMUX_SUBMIT=0' >&2
  exit 1
fi
echo 'PASS: explicit 0 stops typing'

# --- LETTERBOX_CMUX_SUBMIT=1: still submits ---
LETTERBOX_CMUX_SUBMIT=1 run_adapter
grep -qE '^send --surface ' "$work/cmux-calls.log" || {
  echo 'FAIL: expected cmux send with LETTERBOX_CMUX_SUBMIT=1' >&2
  cat "$work/cmux-calls.log" >&2
  exit 1
}
grep -qE '^send-key --surface .* Enter$' "$work/cmux-calls.log" || {
  echo 'FAIL: expected cmux send-key Enter with LETTERBOX_CMUX_SUBMIT=1' >&2
  cat "$work/cmux-calls.log" >&2
  exit 1
}
echo 'PASS: explicit 1 submits the doorbell'

printf 'cmux-doorbell-safety test: PASS\n'
