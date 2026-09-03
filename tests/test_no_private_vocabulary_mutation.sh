#!/usr/bin/env bash
# Mutation: the private-vocabulary gate must catch residue wherever it lands —
# visible file, hidden dotfile, and .github workflow — failing with file:line.
# Sub-run output is [mut]-prefixed so an expected inner FAIL is never mistaken
# for a real one by anything grepping this log.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
gate_name="test_no_private_vocabulary.sh"

tmp="$(mktemp -d "${TMPDIR:-/tmp}/vocab-mut.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT

# Self-contained copy of the repo (including .git so ls-files enumeration runs).
cp -R "$root"/. "$tmp/repo/"

fails=0
plant_and_run() { # $1 relative residue path
  local rel="$1" out rc
  mkdir -p "$tmp/repo/$(dirname "$rel")"
  printf 'residue tele''gram here\n' > "$tmp/repo/$rel"
  git -C "$tmp/repo" add -f "$rel"
  out="$(mktemp)"
  set +e
  ( cd "$tmp/repo" && "./tests/$gate_name" ) >"$out" 2>&1
  rc=$?
  set -e
  echo "[mut] --- residue at $rel → gate rc=$rc ---"
  sed 's/^/[mut] /' "$out"
  if [[ "$rc" -eq 0 ]]; then
    echo "FAIL: [mut] gate passed with residue at $rel" >&2
    fails=$((fails + 1))
  elif ! grep -Fq "$rel:" "$out"; then
    echo "FAIL: [mut] hit missing file:line for $rel" >&2
    fails=$((fails + 1))
  else
    echo "PASS: [mut] gate failed with file:line for $rel"
  fi
  git -C "$tmp/repo" rm -q --cached "$rel" 2>/dev/null || true
  rm -f "$tmp/repo/$rel"
  rm -f "$out"
}

for rel in "docs/visible-residue.md" ".github/workflows/residue-ci.yml" ".hidden-residuerc"; do
  plant_and_run "$rel"
done

# Line wrap must not evade the gate (two-word private phrase split by newline).
wrap_rel="docs/wrap-residue.md"
mkdir -p "$tmp/repo/docs"
printf 'residue shared''\n''brain here\n' > "$tmp/repo/$wrap_rel"
git -C "$tmp/repo" add -f "$wrap_rel"
wrap_out="$(mktemp)"
set +e
( cd "$tmp/repo" && "./tests/$gate_name" ) >"$wrap_out" 2>&1
wrap_rc=$?
set -e
echo "[mut] --- wrap residue at $wrap_rel → gate rc=$wrap_rc ---"
sed 's/^/[mut] /' "$wrap_out"
if [[ "$wrap_rc" -eq 0 ]]; then
  echo "FAIL: [mut] gate passed with wrapped private phrase at $wrap_rel" >&2
  fails=$((fails + 1))
elif ! grep -Fq "$wrap_rel:" "$wrap_out"; then
  echo "FAIL: [mut] wrap hit missing file:line for $wrap_rel" >&2
  fails=$((fails + 1))
else
  echo "PASS: [mut] gate failed with file:line for wrapped phrase at $wrap_rel"
fi
git -C "$tmp/repo" rm -q --cached "$wrap_rel" 2>/dev/null || true
rm -f "$tmp/repo/$wrap_rel" "$wrap_out"

# Clean tree must pass, or every assertion above is meaningless.
if (cd "$tmp/repo" && "./tests/$gate_name" >/dev/null 2>&1); then
  echo "PASS: gate passes on a clean tree"
else
  echo "FAIL: gate fails on a clean tree — the assertions above prove nothing" >&2
  fails=$((fails + 1))
fi

if [[ "$fails" -ne 0 ]]; then
  echo "vocabulary-gate mutation: FAIL ($fails)" >&2
  exit 1
fi
echo "vocabulary-gate mutation: PASS"
exit 0
