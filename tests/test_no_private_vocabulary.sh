#!/usr/bin/env bash
# test_no_private_vocabulary.sh — product-cleanliness gate, separate from
# test_no_private_data.sh (personal paths/secrets).
#
# Scans EVERY tracked file (git ls-files -z), not a directory allowlist.
# An allowlist misses root dotted dirs such as .github/.
#
# Hits report file:line. grep -nFI per file so the filename is always
# printed (rg -I means --no-filename and skips hidden files).
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"; cd "$root"
self_name="$(basename "$0")"
self_path="tests/$self_name"

# Forbidden tokens (fixed baseline — do not weaken per-port).
# Built from parts so this file is not a self-hit if ever scanned.
patterns=(
  "shared""-brain"
  "bus ""doorbell"
  "BUS_""AGENT"
  "BUS_""DIR"
  "tele""gram"
  "launch""d"
  "kimik""357"
  "utc_""now"
)

# Exactly the files that ship, including hidden files and dotted dirs.
# find fallback is for a non-git checkout and still includes hidden paths.
list_files() {
  if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    git ls-files -z
  else
    find . -type f -not -path './.git/*' -print0
  fi
}

# Print "path:line:text" hits for one token. Filename comes from the loop.
hits_for() {
  local pat="$1" f m
  while IFS= read -r -d '' f; do
    f="${f#./}"
    [[ "$f" == "$self_path" ]] && continue
    [[ -f "$f" ]] || continue
    while IFS= read -r m; do
      [[ -z "$m" ]] && continue
      printf '%s:%s\n' "$f" "$m"
    done < <(grep -nFI -- "$pat" "$f" 2>/dev/null || true)
  done < <(list_files)
}

fails=0
echo "private-vocabulary sweep: scanning every tracked file..."

for pat in "${patterns[@]}"; do
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    echo "FAIL: private vocabulary '$pat' at $line" >&2
    fails=$((fails + 1))
  done < <(hits_for "$pat")
done

# Multi-word phrases survive a line wrap. Collapse whitespace, then match.
wrap_pats=("shared"" brain" "bus ""doorbell")
while IFS= read -r -d '' f; do
  f="${f#./}"
  [[ "$f" == "$self_path" || "$f" == "tests/vocab_normalized.py" ]] && continue
  [[ -f "$f" ]] || continue
  while IFS= read -r hit; do
    [[ -z "$hit" ]] && continue
    echo "FAIL: private vocabulary (whitespace-normalised) at $hit" >&2
    fails=$((fails + 1))
  done < <(python3 tests/vocab_normalized.py "$f" "${wrap_pats[@]}" 2>/dev/null || true)
done < <(list_files)

if (( fails > 0 )); then
  printf 'no-private-vocabulary: FAIL (%d hit(s))\n' "$fails" >&2
  exit 1
fi

printf 'no-private-vocabulary: PASS\n'
exit 0
