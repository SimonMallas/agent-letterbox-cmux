#!/usr/bin/env bash
# If letter_epoch substitutes date -u +%s for a valid old mtime, the
# epoch suite must fail (stale-days oracle).
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
src="$root/bin/letterbox"
suite="$root/tests/test_letter_epoch_stat.sh"
[[ -x "$src" && -x "$suite" ]] || { echo "FAIL: missing helper or suite" >&2; exit 1; }

work="$(mktemp -d "${TMPDIR:-/tmp}/lb-epoch-mut.XXXXXX")"
trap 'rm -rf "$work"' EXIT

python3 - "$src" "$work/letterbox.now" <<'PY'
import pathlib, sys
src = pathlib.Path(sys.argv[1]).read_text()
dst = pathlib.Path(sys.argv[2])
old = """    if ep=\"$(mtime_epoch_probe stat -f %m \"$file\")\"; then
      printf '%s\\n' \"$ep\"
      return 0
    fi"""
new = """    if ep=\"$(mtime_epoch_probe stat -f %m \"$file\")\"; then
      date -u +%s
      return 0
    fi"""
if old not in src:
    raise SystemExit("mtime-success mutation did not apply")
dst.write_text(src.replace(old, new, 1))
dst.chmod(0o755)
PY

set +e
out="$(LETTERBOX_BIN="$work/letterbox.now" "$suite" 2>&1)"
rc=$?
set -e
echo "$out"
if [[ "$rc" -eq 0 ]]; then
  echo "FAIL: epoch suite passed after substituting date for old mtime" >&2
  exit 1
fi
echo "PASS: epoch suite failed as intended (rc=$rc)"
echo "letter-epoch-stat mutation: PASS"
