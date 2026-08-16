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

if [[ "$fails" -ne 0 ]]; then
  echo "vocabulary-gate mutation: FAIL ($fails)" >&2
  exit 1
fi
echo "vocabulary-gate mutation: PASS"
exit 0
