#!/usr/bin/env bash
# letter_epoch: mtime probes may print garbage and still exit 0 (GNU
# `stat -f` is filesystem mode). Only a numeric epoch may be used.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
letterbox="$root/bin/letterbox"
work="$(mktemp -d "${TMPDIR:-/tmp}/lb-epoch.XXXXXX")"
trap 'rm -rf "$work"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "PASS: $*"; }

box="$work/box"
LETTERBOX_DIR="$box" "$letterbox" init alpha beta >/dev/null

plant() {
  cat > "$box/beta/inbox/nots.md" <<'EOF'
---
id: body-keys-ok
from: alpha
to: beta
type: info
re:
priority: next
requires_ack: false
deadline:
---
body
EOF
}

install_stat() {
  local dir="$1" body="$2"
  mkdir -p "$dir"
  printf '%s\n' "$body" > "$dir/stat"
  chmod +x "$dir/stat"
}

# GNU-like: -f prints filesystem banner and exits 0; -c %Y is the real mtime.
install_stat "$work/gnu" "$(cat <<'EOF'
#!/usr/bin/env bash
echo "stat $*" >> "${STATLOG:-/dev/null}"
if [[ "${1:-}" == "-f" ]]; then
  echo '  File: "'"${3:-%m}"'"'
  echo '    ID: 100000000h namelen=255'
  exit 0
fi
if [[ "${1:-}" == "-c" && "${2:-}" == "%Y" ]]; then
  /usr/bin/stat -f %m "${3:?}"
  exit $?
fi
exit 1
EOF
)"

# BSD-like: -f %m prints digits; -c must not be required.
install_stat "$work/bsd" "$(cat <<'EOF'
#!/usr/bin/env bash
echo "stat $*" >> "${STATLOG:-/dev/null}"
if [[ "${1:-}" == "-f" && "${2:-}" == "%m" ]]; then
  /usr/bin/stat -f %m "${3:?}"
  exit $?
fi
if [[ "${1:-}" == "-c" ]]; then
  echo "GNU_FALLBACK_USED" >> "${STATLOG:-/dev/null}"
  exit 1
fi
exit 1
EOF
)"

# Both probes fail (non-numeric or nonzero): date fallback still numeric.
install_stat "$work/dead" "$(cat <<'EOF'
#!/usr/bin/env bash
echo "stat $*" >> "${STATLOG:-/dev/null}"
if [[ "${1:-}" == "-f" ]]; then
  echo '  File: "garbage"'
  exit 0
fi
if [[ "${1:-}" == "-c" ]]; then
  echo 'not-a-number'
  exit 0
fi
exit 1
EOF
)"

run_check() {
  local mockdir="$1" log="$2"
  plant
  STATLOG="$log" PATH="$mockdir:$PATH" \
    LETTERBOX_DIR="$box" LETTERBOX_AGENT=beta "$letterbox" check >"$work/out" 2>"$work/err" || {
    echo "check stderr:" >&2
    cat "$work/err" >&2
    fail "check died with mock $(basename "$mockdir")"
  }
  if grep -q 'unbound variable' "$work/err" "$work/out"; then
    fail "unbound variable leaked: $(cat "$work/err")"
  fi
  grep -q 'inbox:' "$work/out" || fail "check missing inbox line"
}

rm -f "$box/beta/inbox"/*.md
: > "$work/gnu.log"
run_check "$work/gnu" "$work/gnu.log"
grep -q -- '-f' "$work/gnu.log" || fail "GNU mock never saw -f"
grep -q -- '-c %Y' "$work/gnu.log" || fail "GNU mock never reached -c %Y fallback"
pass "GNU-like stat -f garbage is ignored; -c %Y used; check lives"

rm -f "$box/beta/inbox"/*.md
: > "$work/bsd.log"
run_check "$work/bsd" "$work/bsd.log"
grep -q -- '-f %m' "$work/bsd.log" || fail "BSD mock never saw -f %m"
if grep -q GNU_FALLBACK_USED "$work/bsd.log"; then
  fail "BSD success still ran GNU -c"
fi
pass "BSD-like stat -f %m numeric success is kept; GNU probe not required"

rm -f "$box/beta/inbox"/*.md
: > "$work/dead.log"
run_check "$work/dead" "$work/dead.log"
pass "both probes non-numeric: date fallback; check lives"

rm -f "$box/beta/inbox"/*.md
plant
STATLOG="$work/gnu2.log" PATH="$work/gnu:$PATH" \
  LETTERBOX_DIR="$box" LETTERBOX_AGENT=beta "$letterbox" check >/dev/null
pass "no-timestamp id letter (body-keys-ok) survives GNU stat on check"

echo "letter-epoch-stat: PASS"
