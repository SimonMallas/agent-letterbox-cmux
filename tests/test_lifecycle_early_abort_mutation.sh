#!/usr/bin/env bash
# Mutation: early exit 0 and set -e abort after assertion 1 on each lifecycle
# suite must be non-zero and must report an explicit incomplete-footer failure.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"

fails=0
prove() {
  local suite="$1" kind="$2" envname="$3" footer="$4" later="$5" hook="$6"
  local out rc
  out="$(mktemp)"
  set +e
  env "$envname=1" "$suite" >"$out" 2>&1
  rc=$?
  set -e
  echo "--- $suite $kind rc=$rc ---"
  cat "$out"
  echo "--- end $suite $kind ---"
  if [[ "$rc" -eq 0 ]]; then
    echo "FAIL: $suite $kind returned rc=0" >&2
    fails=$((fails + 1))
  fi
  if grep -qxF "$footer" "$out"; then
    echo "FAIL: $suite $kind printed success footer" >&2
    fails=$((fails + 1))
  fi
  if ! grep -qE 'FAIL \(early abort|pass count|incomplete' "$out"; then
    echo "FAIL: $suite $kind missing explicit count/footer failure" >&2
    fails=$((fails + 1))
  fi
  if grep -qF "$later" "$out"; then
    echo "FAIL: $suite $kind ran past first assertion" >&2
    fails=$((fails + 1))
  fi
  if ! grep -qF "$hook" "$out"; then
    echo "FAIL: $suite $kind mutation hook did not fire" >&2
    fails=$((fails + 1))
  fi
  rm -f "$out"
}

prove "$root/tests/test_lifecycle_v02.sh" exit0 LETTERBOX_MUTATE_EARLY_EXIT0 \
  'lifecycle v0.2: PASS' 'PASS: B2-result-terminal' \
  'MUTATION: early exit 0 after first assertion'
prove "$root/tests/test_lifecycle_v02.sh" sete LETTERBOX_MUTATE_EARLY_ABORT \
  'lifecycle v0.2: PASS' 'PASS: B2-result-terminal' \
  'MUTATION: set-e abort after first assertion'
prove "$root/tests/test_lifecycle_v03.sh" exit0 LETTERBOX_MUTATE_EARLY_EXIT0 \
  'lifecycle v0.3: PASS' 'PASS: A1 ack refused on non-task' \
  'MUTATION: early exit 0 after first assertion'
prove "$root/tests/test_lifecycle_v03.sh" sete LETTERBOX_MUTATE_EARLY_ABORT \
  'lifecycle v0.3: PASS' 'PASS: A1 ack refused on non-task' \
  'MUTATION: set-e abort after first assertion'

if [[ "$fails" -ne 0 ]]; then
  echo "early-abort mutation: FAIL ($fails)" >&2
  exit 1
fi
echo "early-abort mutation: PASS"
exit 0
