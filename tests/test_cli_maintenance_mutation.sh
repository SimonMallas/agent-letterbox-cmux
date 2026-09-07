#!/usr/bin/env bash
# Removing the added token command or stdin hints must fail test_cli_maintenance.sh.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
src="$root/bin/letterbox"
suite="$root/tests/test_cli_maintenance.sh"
[[ -x "$src" && -x "$suite" ]] || { echo "FAIL: missing helper or suite" >&2; exit 1; }

work="$(mktemp -d "${TMPDIR:-/tmp}/lb-cli-mut.XXXXXX")"
trap 'rm -rf "$work"' EXIT
fails=0

run_mut() {
  local name="$1" helper="$2" expect_apply="$3"
  local out rc
  out="$(mktemp "$work/out.XXXXXX")"
  set +e
  LETTERBOX_BIN="$helper" "$suite" >"$out" 2>&1
  rc=$?
  set -e
  echo "--- mutation $name rc=$rc ---"
  cat "$out"
  echo "--- end $name ---"
  if [[ "$rc" -eq 0 ]]; then
    echo "FAIL: $name — suite passed after behaviour was removed" >&2
    fails=$((fails + 1))
  else
    echo "PASS: $name — suite failed as intended (rc=$rc)"
  fi
  if ! grep -qF "$expect_apply" "$helper"; then
    :
  fi
}

python3 - "$src" "$work" <<'PY'
import pathlib, sys
src = pathlib.Path(sys.argv[1]).read_text()
work = pathlib.Path(sys.argv[2])

hint = src.replace(
    "empty message body; pipe the body via stdin (letterbox send <to> <type> <slug> [--now])",
    "empty message body",
).replace(
    "empty reply body; pipe the reply body via stdin (letterbox reply <id> <ack|nack|result> <slug> [--now])",
    "empty reply body",
)
if hint == src:
    raise SystemExit("hint mutation did not apply")
(work / "letterbox.nohint").write_text(hint)
(work / "letterbox.nohint").chmod(0o755)

token = src.replace("token) shift; cmd_token \"$@\";;", "")
if token == src:
    raise SystemExit("token dispatch mutation did not apply")
(work / "letterbox.notoken").write_text(token)
(work / "letterbox.notoken").chmod(0o755)
PY

run_mut "strip-stdin-hint" "$work/letterbox.nohint" "empty message body"
run_mut "strip-token-dispatch" "$work/letterbox.notoken" "cmd_token"

if [[ "$fails" -ne 0 ]]; then
  echo "cli-maintenance mutation: FAIL ($fails)" >&2
  exit 1
fi
echo "cli-maintenance mutation: PASS"
exit 0
