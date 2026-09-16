#!/usr/bin/env bash
# doorbell-line receiver conformance: the vendored doorbell-line fixtures
# against this edition's real parse_doorbell_line (via bin/letterbox
# doorbell-parse). Accepted lines must parse to the expected shape fields;
# rejected lines must be refused. `\n` in a fixture field encodes a newline.
# Skips cleanly when this repo carries no vendored fixture snapshot.
set -euo pipefail

EDITION="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
FIX="${2:-$EDITION/conformance/doorbell-outcome-v1}"
if [[ ! -d "$FIX" ]]; then
  echo "SKIP: no vendored doorbell-outcome-v1 fixtures at $FIX"
  exit 0
fi
ROOT="$(mktemp -d /tmp/lb-dl-fixtures.XXXXXX)"
trap 'rm -rf "$ROOT"' EXIT

lb="$EDITION/bin/letterbox"
pass=0; fail=0

run_parser() { # $1=line
  BOX="$ROOT/box" LETTERBOX_DIR="$ROOT/box" "$lb" doorbell-parse "$1" 2>/dev/null
}

# Accepted fixture: line<TAB>shape<TAB>note — explicit expected stdout per row.
n=0
while IFS=$'\t' read -r line shape note; do
  [[ "$line" == \#* || -z "$line" ]] && continue
  n=$((n + 1))
  line="$(printf '%b' "$line")"
  case "$n" in
    1) expected='v02';;
    2) expected='v03 deadbeef';;
    3) expected='v04 agent';;
    4) expected='v04 agent deadbeef';;
    5) expected='v04 agent-2 abcdef01';;
    *) echo "FAIL: unmapped accepted row $n"; fail=$((fail+1)); continue;;
  esac
  if got="$(run_parser "$line")" && [[ "$got" == "$expected" ]]; then
    pass=$((pass+1))
  else
    echo "FAIL accepted #$n: want [$expected] got [${got:-}]"; fail=$((fail+1))
  fi
done < "$FIX/doorbell-line-accepted.tsv"

# Rejected fixture: line<TAB>why — parser must refuse (nonzero exit).
while IFS=$'\t' read -r line why; do
  [[ "$line" == \#* || -z "$line" ]] && continue
  line="$(printf '%b' "$line")"
  if run_parser "$line" >/dev/null 2>&1; then
    echo "FAIL rejected (parser accepted): [$line] ($why)"; fail=$((fail+1))
  else
    pass=$((pass+1))
  fi
done < "$FIX/doorbell-line-rejected.tsv"

echo "──"
if (( fail > 0 )); then
  echo "doorbell-line fixtures: $fail FAIL ($pass pass)"; exit 1
fi
echo "doorbell-line fixtures: all PASS ($pass checks)"
