#!/usr/bin/env bash
# Mutation: the doorbell-docs drift gate must fail when the adapter is gone,
# when the token moves ahead of the tail, when the adapter emits a from-dash
# sender, and when the short README shape is planted in README / SPEC / SKILL.
# Inner output is [mut]-prefixed.
# Clean-tree PASS is required or the plants prove nothing.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
gate="tests/test_doorbell_docs_drift.sh"
wrong='📬 letterbox doorbell: check your inbox'

tmp="$(mktemp -d "${TMPDIR:-/tmp}/drift-mut.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT
cp -R "$root"/. "$tmp/repo/"

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

plat=""
for c in cmux tmux herdr zellij; do
  if [[ -x "$root/adapters/$c.sh" ]]; then plat="$c"; break; fi
done
adpt="adapters/${plat}.sh"
echo "[mut] --- delete $adpt ---"
rm -f "$tmp/repo/$adpt"
run_gate
if [[ "$LAST_RC" -eq 0 ]]; then
  echo "FAIL: [mut] gate passed with adapter deleted — would be vacuous" >&2
  fails=$((fails + 1))
elif ! printf '%s\n' "$LAST_OUT" | grep -q 'would be vacuous'; then
  echo "FAIL: [mut] adapter-delete did not report vacuous" >&2
  fails=$((fails + 1))
else
  echo "PASS: [mut] deleting the adapter fails the gate (vacuous)"
fi
cp "$root/$adpt" "$tmp/repo/$adpt"

echo "[mut] --- move token ahead of the tail ---"
if python3 - "$tmp/repo/$adpt" "$plat" <<'PY'
from pathlib import Path
import sys
p = Path(sys.argv[1])
plat = sys.argv[2]
t = p.read_text()
pairs = {
    "cmux": (
        'line="$line · $token"',
        'line="${line% — please check} · $token — please check"',
    ),
    "tmux": (
        'line="$line · $tok"',
        'line="${line% — please check} · $tok — please check"',
    ),
    "herdr": (
        'line="$line · $token"',
        'line="${line% — please check} · $token — please check"',
    ),
    "zellij": (
        'line="${line} · ${tok}"',
        'line="${line% — please check} · ${tok} — please check"',
    ),
}
old, new = pairs[plat]
if old not in t:
    raise SystemExit(3)
p.write_text(t.replace(old, new, 1))
PY
then
  run_gate
  if [[ "$LAST_RC" -eq 0 ]]; then
    echo "FAIL: [mut] gate passed after moving the token ahead of the tail" >&2
    fails=$((fails + 1))
  else
    echo "PASS: [mut] token-ahead adapter fails the gate"
  fi
else
  echo "FAIL: [mut] token-ahead mutation did not apply" >&2
  fails=$((fails + 1))
fi
cp "$root/$adpt" "$tmp/repo/$adpt"

echo "[mut] --- emit a from-dash sender ---"
if python3 - "$tmp/repo/$adpt" "$plat" <<'PY'
from pathlib import Path
import sys
p = Path(sys.argv[1])
plat = sys.argv[2]
t = p.read_text()
pairs = {
    "cmux": (' from $from in ', ' from - in '),
    "tmux": (' from $line_from in ', ' from - in '),
    "herdr": (' from $line_from in ', ' from - in '),
    "zellij": (' from ${line_from} in ', ' from - in '),
}
old, new = pairs[plat]
if old not in t:
    raise SystemExit(3)
p.write_text(t.replace(old, new, 1))
PY
then
  run_gate
  if [[ "$LAST_RC" -eq 0 ]]; then
    echo "FAIL: [mut] gate passed with a from-dash sender emitted" >&2
    fails=$((fails + 1))
  else
    echo "PASS: [mut] from-dash sender fails the gate"
  fi
else
  echo "FAIL: [mut] from-dash mutation did not apply" >&2
  fails=$((fails + 1))
fi
cp "$root/$adpt" "$tmp/repo/$adpt"

plant() {
  local rel="$1"
  local file="$tmp/repo/$rel"
  printf '\n%s\n' "$wrong" >> "$file"
  echo "[mut] --- plant short line in $rel ---"
  run_gate
  if [[ "$LAST_RC" -eq 0 ]]; then
    echo "FAIL: [mut] gate passed with short line planted in $rel" >&2
    fails=$((fails + 1))
  elif ! printf '%s\n' "$LAST_OUT" | grep -E -q "$rel:[0-9]+"; then
    echo "FAIL: [mut] plant in $rel missing file:line" >&2
    fails=$((fails + 1))
  else
    echo "PASS: [mut] planted short line in $rel fails with file:line"
  fi
  cp "$root/$rel" "$file"
}

plant README.md
plant SPEC.md
plant skills/agent-letterbox/SKILL.md
# Prove the widened git ls-files scope, not just the old allowlist.
plant docs/why-letterbox.md

echo "[mut] --- clean tree ---"
if ( cd "$tmp/repo" && "./$gate" >/dev/null 2>&1 ); then
  echo "PASS: gate passes on a clean tree"
else
  echo "FAIL: gate fails on a clean tree — the assertions above prove nothing" >&2
  fails=$((fails + 1))
fi

if [[ "$fails" -ne 0 ]]; then
  echo "doorbell-docs-drift mutation: FAIL ($fails)" >&2
  exit 1
fi
echo "doorbell-docs-drift mutation: PASS"
exit 0
