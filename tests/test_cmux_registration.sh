#!/usr/bin/env bash
# Mock-backed self-registration proof: no title pattern is needed for a live
# agent that records its current cmux surface.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
letterbox="$root/bin/letterbox"
adapter="$root/adapters/cmux.sh"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin"

cat > "$tmp/bin/cmux" <<'MOCK'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$CMUX_LOG"
case "$1" in
  tree) echo 'surface:7 [terminal] "dynamic agent"' ;;
esac
MOCK
chmod +x "$tmp/bin/cmux"
export PATH="$tmp/bin:$PATH"
export CMUX_LOG="$tmp/cmux.log"
export LETTERBOX_DIR="$tmp/box"
export LETTERBOX_CMUX_REGISTRY="$tmp/box/cmux-agents.tsv"

CMUX_SURFACE_ID=surface:7 "$letterbox" cmux register receiver
awk -F $'\t' '$1 == "receiver" && $2 == "surface:7" { found=1 } END { exit !found }' "$LETTERBOX_CMUX_REGISTRY"

if CMUX_SURFACE_ID=surface:7 "$letterbox" cmux register other-agent; then
  echo 'FAIL: duplicate live surface registration was accepted' >&2
  exit 1
fi

LETTERBOX_CMUX_SUBMIT=1 "$adapter" receiver delegate dynamic-registration
grep -F 'send --surface surface:7' "$CMUX_LOG" >/dev/null
grep -F 'send-key --surface surface:7 Enter' "$CMUX_LOG" >/dev/null
printf '%s\n' 'cmux self-registration test: PASS'
