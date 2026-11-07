#!/usr/bin/env bash
# The lock primitive must stay exclusive even when the platform's mkdir lies.
# uutils coreutils 0.10.0 (Ubuntu 25.10+, 26.04 LTS, GitHub ubuntu-latest) exits 0
# under a race even when its mkdir(2) fails with EEXIST. The shim below reproduces
# that behaviour deterministically on any OS: plain mkdir calls always report
# success. Locks must be taken by a real syscall, not by trusting the binary.
set -uo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
letterbox="$root/bin/letterbox"
box="$(mktemp -d)"
shim="$(mktemp -d)"
noperl=""
trap 'rm -rf "$box" "$shim" ${noperl:+"$noperl"}' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "PASS: $*"; }

real_mkdir="$(command -v mkdir)"
cat > "$shim/mkdir" <<EOF
#!/bin/sh
# Lying mkdir: plain creates always report success (the uutils 0.10.0 bug).
case " \$* " in *" -p "*) exec "$real_mkdir" "\$@";; esac
"$real_mkdir" "\$@" 2>/dev/null
exit 0
EOF
chmod +x "$shim/mkdir"

# Sanity: the shim lies as intended.
"$shim/mkdir" "$box/x" || fail "shim broken: first create failed"
"$shim/mkdir" "$box/x" 2>/dev/null || fail "shim broken: lying create failed"

lb() {
  local agent="$1"; shift
  PATH="$shim:$PATH" LETTERBOX_DIR="$box" LETTERBOX_AGENT="$agent" "$letterbox" "$@"
}

LETTERBOX_DIR="$box" "$letterbox" init alpha beta >/dev/null

printf '%s\n' '=== letterbox lock: at most one winner with a lying mkdir ==='
rounds=30
double=0
for i in $(seq "$rounds"); do
  pa=$(mktemp); pb=$(mktemp)
  PATH="$shim:$PATH" LETTERBOX_DIR="$box" LETTERBOX_AGENT=alpha "$letterbox" lock "res2-$i" >"$pa" 2>/dev/null &
  PATH="$shim:$PATH" LETTERBOX_DIR="$box" LETTERBOX_AGENT=beta "$letterbox" lock "res2-$i" >"$pb" 2>/dev/null &
  wait
  if grep -q '^locked:' "$pa" && grep -q '^locked:' "$pb"; then double=$((double+1)); fi
  lb alpha unlock "res2-$i" >/dev/null 2>&1 || true
  lb beta unlock "res2-$i" >/dev/null 2>&1 || true
  rm -f "$pa" "$pb"
done
[[ "$double" -eq 0 ]] || fail "letterbox lock: both racers reported 'locked:' in $double of $rounds rounds"
pass "letterbox lock exclusive with a lying mkdir ($rounds rounds)"

printf '%s\n' '=== terminal replies: at most one publishes with a lying mkdir ==='
# Same race as tests/test_stale_lifecycle_lock_race.py, but the shim makes the
# platform lie on EVERY call, so no timing window is needed.
if PATH="$shim:$PATH" python3 -B "$root/tests/test_stale_lifecycle_lock_race.py" >/dev/null 2>&1; then
  pass "reply race exclusive with a lying mkdir"
else
  fail "reply race: two terminal replies published with a lying mkdir"
fi


printf '%s\n' '=== no perl: locks fail closed with a clear reason ==='
noperl="$(mktemp -d)"
for t in bash dirname date mkdir od tr awk grep mktemp mv basename cat rmdir rm shasum ln sed python3; do
  src="$(command -v "$t")" && ln -s "$src" "$noperl/$t"
done
out=$(PATH="$noperl" LETTERBOX_DIR="$box" LETTERBOX_AGENT=alpha "$letterbox" lock no-perl-probe 2>&1)
rc=$?
[[ $rc -ne 0 ]] || fail "lock without perl succeeded"
printf '%s' "$out" | grep -q "needs perl" || fail "unclear refusal without perl: $out"
pass "lock without perl refuses with a named reason"
echo "lock exclusivity: PASS"
