#!/usr/bin/env bash
# --help prints usage and exits 0, with no agent name or mailbox set.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
lb() { env -u LETTERBOX_AGENT -u LETTERBOX_DIR -u LETTERBOX_NOTES_DIR "$root/bin/letterbox" "$@"; }

for flag in --help -h help; do
  out="$(lb "$flag")"
  [[ "$out" == 'usage: letterbox <command>'* ]] || { echo "FAIL: letterbox $flag"; exit 1; }
done
for cmd in send check reply file read progress nudge ring query lint-notes cmux; do
  for flag in --help -h; do
    out="$(lb "$cmd" "$flag")"
    [[ "$out" == "usage: letterbox $cmd"* ]] || { echo "FAIL: letterbox $cmd $flag: $out"; exit 1; }
  done
done
# Help must never be taken for an argument: a missing command still fails.
if lb >/dev/null 2>&1; then echo 'FAIL: bare letterbox should exit non-zero'; exit 1; fi
echo 'help: ok'
