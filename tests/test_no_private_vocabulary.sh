#!/usr/bin/env bash
# test_no_private_vocabulary.sh — product-cleanliness gate, separate from
# test_no_private_data.sh (personal paths/secrets).
#
# Fails make test with file:line for internal/private porting residue.
# Baseline is identical across public cmux/tmux/herdr/zellij ports.
set -uo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"; cd "$root"
self="tests/$(basename "$0")"

# Patterns are the private residue list. This file is excluded from the scan.
patterns=(
  'shared-brain'
  'bus doorbell'
  'BUS_AGENT'
  'BUS_DIR'
  'telegram'
  'launchd'
  'kimik357'
  'utc_now'
)

# Tracked files in the required sweep set only.
files="$(git ls-files -- bin adapters tests docs Makefile SPEC.md README.md skills CHANGELOG.md CONTRIBUTING.md SECURITY.md ROADMAP.md 2>/dev/null | grep -v -e "^$self\$" || true)"
[[ -n "$files" ]] || { echo "no-private-vocabulary: no tracked files in sweep set?" >&2; exit 1; }

fails=0
while IFS= read -r f; do
  [[ -n "$f" && -f "$f" ]] || continue
  for pat in "${patterns[@]}"; do
    hits="$(grep -nF -e "$pat" "$f" 2>/dev/null || true)"
    [[ -z "$hits" ]] && continue
    while IFS= read -r line; do
      printf 'FAIL: private vocabulary %s\n  %s:%s\n' "$pat" "$f" "$line" >&2
      fails=$((fails + 1))
    done <<< "$hits"
  done
done <<< "$files"

if (( fails > 0 )); then
  printf 'no-private-vocabulary: FAIL (%d hit(s))\n' "$fails" >&2
  exit 1
fi
printf 'no-private-vocabulary: PASS\n'
