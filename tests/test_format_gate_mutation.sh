#!/usr/bin/env bash
# Mutation: the format-gate leaf baseline is a frozen pre-gate fixture.
# Replacing that fixture with the candidate must fail closed. A one-line
# stdout change in the frozen baseline must break leaf parity. The copy has
# no git, so an archive of HEAD cannot be the oracle.
# Clean-tree PASS is required or the plants prove nothing.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
gate="tests/test_format_gate.sh"
fix="tests/fixtures/letterbox-before-ring-retry"

tmp="$(mktemp -d "${TMPDIR:-/tmp}/fmt-gate-mut.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/repo"
tar -C "$root" --exclude .git --exclude __pycache__ -cf - . | tar -C "$tmp/repo" -xf -
[[ ! -e "$tmp/repo/.git" ]] || {
  echo "FAIL: [mut] copy still has git" >&2
  exit 1
}

fails=0
run_gate() {
  local out rc
  out="$(mktemp)"
  set +e
  ( cd "$tmp/repo" && "./$gate" ) >"$out" 2>&1
  rc=$?
  set -e
  sed 's/^/[mut] /' "$out"
  LAST_OUT="$(cat "$out")"
  LAST_RC=$rc
  rm -f "$out"
  return 0
}

echo "[mut] --- clean tree ---"
run_gate
if [[ "$LAST_RC" -ne 0 ]] || ! printf '%s\n' "$LAST_OUT" | grep -q 'format gate: PASS'; then
  echo "FAIL: [mut] clean tree did not pass — plants would prove nothing" >&2
  fails=$((fails + 1))
else
  echo "PASS: [mut] clean tree passes"
fi

echo "[mut] --- baseline replaced by the candidate ---"
cp "$tmp/repo/bin/letterbox" "$tmp/repo/$fix"
run_gate
if [[ "$LAST_RC" -eq 0 ]]; then
  echo "FAIL: [mut] gate passed with the baseline equal to the candidate" >&2
  fails=$((fails + 1))
elif ! printf '%s\n' "$LAST_OUT" | grep -q 'baseline letterbox is the candidate'; then
  echo "FAIL: [mut] candidate baseline did not report non-identity" >&2
  fails=$((fails + 1))
else
  echo "PASS: [mut] candidate baseline fails closed"
fi
cp "$root/$fix" "$tmp/repo/$fix"
chmod +x "$tmp/repo/$fix"

echo "[mut] --- frozen baseline prints an extra line ---"
if [[ "$(head -n 1 "$tmp/repo/$fix")" != '#!/usr/bin/env bash' ]]; then
  echo "FAIL: [mut] baseline shebang missing" >&2
  fails=$((fails + 1))
else
  awk 'NR==1 { print; print "echo MUTATED_PARITY"; next } { print }' \
    "$tmp/repo/$fix" > "$tmp/repo/$fix.mut"
  mv "$tmp/repo/$fix.mut" "$tmp/repo/$fix"
  chmod +x "$tmp/repo/$fix"
  if [[ "$(sed -n '2p' "$tmp/repo/$fix")" != 'echo MUTATED_PARITY' ]]; then
    echo "FAIL: [mut] extra line was not planted" >&2
    fails=$((fails + 1))
  else
    run_gate
    if [[ "$LAST_RC" -eq 0 ]]; then
      echo "FAIL: [mut] gate passed after the frozen baseline gained a stdout line" >&2
      fails=$((fails + 1))
    elif ! printf '%s\n' "$LAST_OUT" | grep -q 'leaf parity stdout'; then
      echo "FAIL: [mut] extra baseline line did not break leaf parity" >&2
      fails=$((fails + 1))
    else
      echo "PASS: [mut] extra baseline line fails leaf parity"
    fi
  fi
fi

readers() {
  local out rc
  out="$(mktemp)"
  set +e
  ( cd "$tmp/repo" && python3 -B tests/test_format_gate_readers.py ) >"$out" 2>&1
  rc=$?
  set -e
  sed 's/^/[mut] /' "$out"
  LAST_OUT="$(cat "$out")"
  LAST_RC=$rc
  rm -f "$out"
  return 0
}

echo "[mut] --- readers baseline on a tree with no git ---"
readers
if [[ "$LAST_RC" -ne 0 ]] || printf '%s\n' "$LAST_OUT" | grep -q 'skipped'; then
  echo "FAIL: [mut] readers baseline skipped or failed on a tree with no git" >&2
  fails=$((fails + 1))
else
  echo "PASS: [mut] readers baseline runs with no git"
fi

echo "[mut] --- readers baseline file removed ---"
rm -f "$tmp/repo/tests/fixtures/pre-gate/lib/query/strict.py"
readers
if [[ "$LAST_RC" -eq 0 ]] || printf '%s\n' "$LAST_OUT" | grep -q 'skipped'; then
  echo "FAIL: [mut] readers baseline skipped or passed with the fixture missing" >&2
  fails=$((fails + 1))
elif ! printf '%s\n' "$LAST_OUT" | grep -q 'baseline pre-gate fixture is missing'; then
  echo "FAIL: [mut] missing readers baseline did not fail closed" >&2
  fails=$((fails + 1))
else
  echo "PASS: [mut] missing readers baseline fails closed"
fi
cp "$root/tests/fixtures/pre-gate/lib/query/strict.py" \
  "$tmp/repo/tests/fixtures/pre-gate/lib/query/strict.py"

echo "[mut] --- readers baseline replaced by the candidate ---"
cp "$tmp/repo/lib/query/strict.py" "$tmp/repo/tests/fixtures/pre-gate/lib/query/strict.py"
readers
if [[ "$LAST_RC" -eq 0 ]] || printf '%s\n' "$LAST_OUT" | grep -q 'skipped'; then
  echo "FAIL: [mut] readers baseline skipped or passed when it was the candidate" >&2
  fails=$((fails + 1))
elif ! printf '%s\n' "$LAST_OUT" | grep -q 'baseline strict.py is the candidate'; then
  echo "FAIL: [mut] candidate readers baseline did not report non-identity" >&2
  fails=$((fails + 1))
else
  echo "PASS: [mut] candidate readers baseline fails closed"
fi

if [[ "$fails" -ne 0 ]]; then
  echo "format-gate mutation: FAIL ($fails)" >&2
  exit 1
fi
echo "format-gate mutation: PASS"
exit 0
