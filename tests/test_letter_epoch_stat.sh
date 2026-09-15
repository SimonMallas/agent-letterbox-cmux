#!/usr/bin/env bash
# letter_epoch: mtime probes are hermetic. Mocks print fixed epochs; they
# never call host stat. GNU-like here means "exit 0 + File: banner", not
# native GNU coreutils.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
letterbox="${LETTERBOX_BIN:-$root/bin/letterbox}"
work="$(mktemp -d "${TMPDIR:-/tmp}/lb-epoch.XXXXXX")"
trap 'rm -rf "$work"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "PASS: $*"; }

# Deterministic oracles (not host mtime).
OLD=1000000000
OTHER=1111111111

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

expect_stale_days() {
  local epoch="$1" now days
  now="$(date -u +%s)"
  days=$(( (now - epoch) / 86400 ))
  grep -q "open: 0 live · 1 stale" "$work/out" || fail "expected 1 stale for epoch $epoch: $(cat "$work/out")"
  if ! grep -q "${days}d" "$work/out"; then
    grep -q "$((days - 1))d" "$work/out" || fail "expected ~${days}d for epoch $epoch: $(cat "$work/out")"
  fi
}

expect_live() {
  grep -q "open: 1 live · 0 stale" "$work/out" || fail "expected live (date fallback): $(cat "$work/out")"
}

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

# GNU-like: -f File: banner exit 0; -c %Y prints OLD. Not native GNU.
install_stat "$work/gnu" "$(cat <<EOF
#!/usr/bin/env bash
echo "stat \$*" >> "\${STATLOG:-/dev/null}"
if [[ "\${1:-}" == "-f" ]]; then
  echo '  File: "'"\${3:-%m}"'"'
  echo '    ID: 100000000h namelen=255'
  exit 0
fi
if [[ "\${1:-}" == "-c" && "\${2:-}" == "%Y" ]]; then
  echo $OLD
  exit 0
fi
exit 1
EOF
)"

# BSD-like: -f %m prints OLD; -c must not run.
install_stat "$work/bsd" "$(cat <<EOF
#!/usr/bin/env bash
echo "stat \$*" >> "\${STATLOG:-/dev/null}"
if [[ "\${1:-}" == "-f" && "\${2:-}" == "%m" ]]; then
  echo $OLD
  exit 0
fi
if [[ "\${1:-}" == "-c" ]]; then
  echo "GNU_FALLBACK_USED" >> "\${STATLOG:-/dev/null}"
  exit 1
fi
exit 1
EOF
)"

# Success + nonnumeric, then nonnumeric GNU: date fallback.
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

# Exit 1 with numeric-looking stdout must be discarded; -c OLD wins? OTHER.
install_stat "$work/exit1" "$(cat <<EOF
#!/usr/bin/env bash
echo "stat \$*" >> "\${STATLOG:-/dev/null}"
if [[ "\${1:-}" == "-f" ]]; then
  echo $OLD
  exit 1
fi
if [[ "\${1:-}" == "-c" && "\${2:-}" == "%Y" ]]; then
  echo $OTHER
  exit 0
fi
exit 1
EOF
)"

# First-line numeric + junk: whole output invalid; -c OTHER.
install_stat "$work/prefix" "$(cat <<EOF
#!/usr/bin/env bash
echo "stat \$*" >> "\${STATLOG:-/dev/null}"
if [[ "\${1:-}" == "-f" ]]; then
  printf '%s\\njunk\\n' $OLD
  exit 0
fi
if [[ "\${1:-}" == "-c" && "\${2:-}" == "%Y" ]]; then
  echo $OTHER
  exit 0
fi
exit 1
EOF
)"

# Signed pre-epoch mtime is canonical decimal.
install_stat "$work/signed" "$(cat <<'EOF'
#!/usr/bin/env bash
echo "stat $*" >> "${STATLOG:-/dev/null}"
if [[ "${1:-}" == "-f" && "${2:-}" == "%m" ]]; then
  printf '%s\n' -1
  exit 0
fi
exit 1
EOF
)"

rm -f "$box/beta/inbox"/*.md
: > "$work/gnu.log"
run_check "$work/gnu" "$work/gnu.log"
grep -q -- '-f' "$work/gnu.log" || fail "GNU-like mock never saw -f"
grep -q -- '-c %Y' "$work/gnu.log" || fail "GNU-like mock never reached -c %Y"
expect_stale_days "$OLD"
pass "GNU-like File: banner ignored; -c %Y epoch $OLD observed as stale"

rm -f "$box/beta/inbox"/*.md
: > "$work/bsd.log"
run_check "$work/bsd" "$work/bsd.log"
grep -q -- '-f %m' "$work/bsd.log" || fail "BSD-like mock never saw -f %m"
if grep -q GNU_FALLBACK_USED "$work/bsd.log"; then
  fail "BSD-like success still ran -c"
fi
expect_stale_days "$OLD"
pass "BSD-like -f %m epoch $OLD observed as stale; -c not required"

rm -f "$box/beta/inbox"/*.md
: > "$work/dead.log"
run_check "$work/dead" "$work/dead.log"
expect_live
pass "success+nonnumeric then nonnumeric: date fallback is live 0m"

rm -f "$box/beta/inbox"/*.md
: > "$work/exit1.log"
run_check "$work/exit1" "$work/exit1.log"
expect_stale_days "$OTHER"
pass "exit 1 + numeric stdout discarded; -c epoch $OTHER observed"

rm -f "$box/beta/inbox"/*.md
: > "$work/prefix.log"
run_check "$work/prefix" "$work/prefix.log"
expect_stale_days "$OTHER"
pass "numeric-prefix plus junk rejected; -c epoch $OTHER observed"

rm -f "$box/beta/inbox"/*.md
: > "$work/signed.log"
run_check "$work/signed" "$work/signed.log"
grep -q 'unbound variable' "$work/err" && fail "signed epoch died"
grep -q 'inbox:' "$work/out" || fail "signed epoch lost check"
pass "signed pre-epoch mtime (-1) is accepted; check lives"

echo "letter-epoch-stat: PASS"
