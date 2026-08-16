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

if (( fails > 0 )); then
  printf 'no-private-vocabulary: FAIL (%d hit(s))\n' "$fails" >&2
  exit 1
fi

# Mutation: visible, hidden, and .github/workflow residue must all fail
# with file:line. A directory allowlist would miss the CI plant.
planted="${patterns[2]}"
fixture="$(mktemp -d "${TMPDIR:-/tmp}/lb-vocab-mut.XXXXXX")"
cleanup_fixture() { rm -rf "$fixture"; }
trap cleanup_fixture EXIT
git -C "$fixture" init -q
mkdir -p "$fixture/docs" "$fixture/.github/workflows"
printf 'residue %s\n' "$planted" > "$fixture/docs/visible-plant.txt"
printf 'residue %s\n' "$planted" > "$fixture/docs/.hidden-plant"
printf 'residue %s\n' "$planted" > "$fixture/.github/workflows/plant.yml"
git -C "$fixture" add -A

plant_out="$(cd "$fixture" && hits_for "$planted")"
require_hit() {
  local needle="$1"
  if ! printf '%s\n' "$plant_out" | grep -Eq "$needle"; then
    echo "FAIL: planted residue not reported with file:line: $needle" >&2
    echo "$plant_out" >&2
    exit 1
  fi
}
require_hit 'docs/visible-plant\.txt:[0-9]+:'
require_hit 'docs/\.hidden-plant:[0-9]+:'
require_hit '\.github/workflows/plant\.yml:[0-9]+:'
echo "PASS: planted visible residue reported as file:line"
echo "PASS: planted hidden residue reported as file:line"
echo "PASS: planted .github/workflow residue reported as file:line"

printf 'no-private-vocabulary: PASS\n'
exit 0
