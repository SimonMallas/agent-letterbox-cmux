#!/usr/bin/env bash
# test_no_private_vocabulary.sh — product-cleanliness gate, separate from
# test_no_private_data.sh (personal paths/secrets).
#
# Fails make test with file:line for internal/private porting residue.
# Baseline is identical across public cmux/tmux/herdr/zellij ports.
#
# grep only: rg -I means --no-filename (hits would lack the required
# file:line) and rg skips hidden files by default (dotfile residue would
# escape). grep -RFnI covers both: filename:line output, hidden files included.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"; cd "$root"
self_name="$(basename "$0")"

# Product surface. This script is excluded from hits (patterns live here).
paths=(
  bin
  adapters
  tests
  docs
  Makefile
  SPEC.md
  README.md
  skills
)
for opt in CHANGELOG.md CONTRIBUTING.md SECURITY.md ROADMAP.md VERSION; do
  [[ -e "$opt" ]] && paths+=("$opt")
done

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

search() {
  local pat="$1"
  shift
  grep -RFnI -- "$pat" "$@" 2>/dev/null || true
}

fails=0
echo "private-vocabulary sweep: scanning product paths..."

for pat in "${patterns[@]}"; do
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    case "$line" in
      *"/tests/$self_name:"*|"tests/$self_name:"*) continue;;
    esac
    echo "FAIL: private vocabulary '$pat' at $line" >&2
    fails=$((fails + 1))
  done < <(search "$pat" "${paths[@]}")
done

if (( fails > 0 )); then
  printf 'no-private-vocabulary: FAIL (%d hit(s))\n' "$fails" >&2
  exit 1
fi

# Mutation: planted visible and hidden residue must both fail with file:line.
# A scanner that uses rg -I (no filename) or skips dotfiles would miss one.
planted="${patterns[2]}"
fixture="$(mktemp -d "${TMPDIR:-/tmp}/lb-vocab-mut.XXXXXX")"
cleanup_fixture() { rm -rf "$fixture"; }
trap cleanup_fixture EXIT
mkdir -p "$fixture/docs"
printf 'residue %s\n' "$planted" > "$fixture/docs/visible-plant.txt"
printf 'residue %s\n' "$planted" > "$fixture/docs/.hidden-plant"
plant_out="$(search "$planted" "$fixture/docs")"
if ! printf '%s\n' "$plant_out" | grep -Eq 'visible-plant\.txt:[0-9]+:'; then
  echo "FAIL: visible planted residue was not reported with file:line" >&2
  echo "$plant_out" >&2
  exit 1
fi
if ! printf '%s\n' "$plant_out" | grep -Eq '\.hidden-plant:[0-9]+:'; then
  echo "FAIL: hidden planted residue was not reported with file:line" >&2
  echo "$plant_out" >&2
  exit 1
fi
echo "PASS: planted visible residue reported as file:line"
echo "PASS: planted hidden residue reported as file:line"

printf 'no-private-vocabulary: PASS\n'
exit 0
