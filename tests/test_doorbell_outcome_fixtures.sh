#!/usr/bin/env bash
# doorbell-outcome v=1 fixture ↔ implementation conformance: every accepted
# outcome line must validate AND round-trip through emit_outcome; every
# rejected line must fail validation; emit_outcome must refuse illegal triples.
# Uses the real functions from this edition's bin/letterbox.
set -euo pipefail

EDITION="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
FIX="${2:-$EDITION/conformance/doorbell-outcome-v1}"
if [[ ! -d "$FIX" ]]; then
  echo "SKIP: no vendored doorbell-outcome-v1 fixtures at $FIX"
  exit 0
fi
ROOT="$(mktemp -d /tmp/lb-fixtures.XXXXXX)"
trap 'rm -rf "$ROOT"' EXIT

# Lift the real validator + emitter from the edition (no top-level code run).
sed -n '/^emit_outcome()/,/^}/p' "$EDITION/bin/letterbox" > "$ROOT/fns.sh"
sed -n '/^valid_contract_line()/,/^}/p' "$EDITION/bin/letterbox" >> "$ROOT/fns.sh"
# shellcheck disable=SC1090
source "$ROOT/fns.sh"

pass=0; fail=0

# accepted.tsv: line<TAB>outcome<TAB>reason<TAB>target
while IFS=$'\t' read -r line outcome reason target; do
  [[ "$line" == \#* || -z "$line" ]] && continue
  if ! valid_contract_line "$line"; then
    echo "FAIL accepted (validator): $line"; fail=$((fail+1)); continue
  fi
  got="$(emit_outcome "$outcome" "$reason" "$target")" || {
    echo "FAIL accepted (emitter rc): $line"; fail=$((fail+1)); continue; }
  if [[ "$got" != "$line" ]]; then
    echo "FAIL accepted (round-trip): want=[$line] got=[$got]"; fail=$((fail+1)); continue
  fi
  pass=$((pass+1))
done < "$FIX/accepted.tsv"

# rejected.tsv: line<TAB>why — field 1 may carry leading spaces; keep them.
while IFS=$'\t' read -r line why; do
  [[ "$line" == \#* || -z "$line" ]] && continue
  if valid_contract_line "$line"; then
    echo "FAIL rejected (validator accepted): [$line] ($why)"; fail=$((fail+1)); continue
  fi
  pass=$((pass+1))
done < "$FIX/rejected.tsv"

# Emitter-side: emit_outcome must refuse every illegal triple, even one the
# caller never should pass (it is the last line of defence before printing).
emit_bad=0
for triple in \
  "submitted - -" \
  "pasted_not_submitted enter_failed -" \
  "pasted_not_submitted - -" \
  "no_live_surface - -" \
  "no_live_surface %1 -" \
  "submitted - %" \
  "submitted - %1%" \
  "submitted enter_failed surface:1" \
  "pasted_not_submitted send_failed surface:1" \
  "no_live_surface notify_only surface:1" \
  "delivered - surface:1"; do
  if emit_outcome $triple >/dev/null 2>&1; then
    echo "FAIL emitter accepted illegal triple: $triple"; fail=$((fail+1)); emit_bad=1
  fi
done
(( emit_bad == 0 )) && pass=$((pass+11))

# Emitter-side positive spot checks (legal triples must print).
emit_good=0
for triple in \
  "submitted - surface:1" \
  "submitted - %12" \
  "pasted_not_submitted enter_failed surface:1" \
  "pasted_not_submitted - %1" \
  "no_live_surface helper_timeout -" \
  "no_live_surface future_token -"; do
  emit_outcome $triple >/dev/null 2>&1 || {
    echo "FAIL emitter refused legal triple: $triple"; fail=$((fail+1)); emit_good=1; }
done
(( emit_good == 0 )) && pass=$((pass+6))

# SHA256SUMS internal consistency.
( cd "$FIX" && shasum -a 256 -c SHA256SUMS >/dev/null ) && pass=$((pass+1)) || {
  echo "FAIL SHA256SUMS verification"; fail=$((fail+1)); }

echo "──"
if (( fail > 0 )); then
  echo "fixtures↔validator: $fail FAIL ($pass pass)"; exit 1
fi
echo "fixtures↔validator: all PASS ($pass checks)"
