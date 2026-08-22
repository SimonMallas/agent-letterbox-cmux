#!/usr/bin/env bash
# Regression: current cmux exposes CMUX_SURFACE_ID as a UUID, not surface:N.
# Registration must resolve the CALLER's short ref via `cmux identify` —
# and must not pick up the focused pane's ref from the same JSON.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
letterbox="$root/bin/letterbox"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin"

cat > "$tmp/bin/cmux" <<'MOCK'
#!/usr/bin/env bash
case "$1" in
  identify)
    cat <<'JSON'
{
  "caller" : {
    "pane_ref" : "pane:7",
    "surface_ref" : "surface:7",
    "surface_type" : "terminal"
  },
  "focused" : {
    "pane_ref" : "pane:9",
    "surface_ref" : "surface:9",
    "surface_type" : "terminal"
  }
}
JSON
    ;;
  tree) echo 'surface:7 [terminal] "uuid agent"' ;;
esac
MOCK
chmod +x "$tmp/bin/cmux"
export PATH="$tmp/bin:$PATH"
export LETTERBOX_DIR="$tmp/box"
export LETTERBOX_CMUX_REGISTRY="$tmp/box/cmux-agents.tsv"

# 1. UUID env (current cmux) → registers the CALLER's ref, not focused's
CMUX_SURFACE_ID='2E6536DA-B697-4752-AE52-13217D7208DC' "$letterbox" cmux register uuid-agent
awk -F $'\t' '$1 == "uuid-agent" && $2 == "surface:7" { found=1 } END { exit !found }' "$LETTERBOX_CMUX_REGISTRY"
if grep -F 'surface:9' "$LETTERBOX_CMUX_REGISTRY" >/dev/null; then
  echo 'FAIL: focused surface leaked into the registry' >&2
  exit 1
fi

# 2. Legacy short-ref env still honoured without touching identify
rm -f "$LETTERBOX_CMUX_REGISTRY"
CMUX_SURFACE_ID=surface:7 "$letterbox" cmux register legacy-agent
awk -F $'\t' '$1 == "legacy-agent" && $2 == "surface:7" { found=1 } END { exit !found }' "$LETTERBOX_CMUX_REGISTRY"

# 3. Unset env + identify still resolves the caller
rm -f "$LETTERBOX_CMUX_REGISTRY"
env -u CMUX_SURFACE_ID "$letterbox" cmux register bare-agent
awk -F $'\t' '$1 == "bare-agent" && $2 == "surface:7" { found=1 } END { exit !found }' "$LETTERBOX_CMUX_REGISTRY"

# 4. caller null (no pane ancestry) → must die, never register the focused pane
cat > "$tmp/bin/cmux" <<'MOCK'
#!/usr/bin/env bash
case "$1" in
  identify)
    printf '{\n  "caller" : null,\n  "focused" : {\n    "surface_ref" : "surface:9"\n  }\n}\n'
    ;;
  tree) echo 'surface:9 [terminal] "focused pane"' ;;
esac
MOCK
chmod +x "$tmp/bin/cmux"
rm -f "$LETTERBOX_CMUX_REGISTRY"
if env -u CMUX_SURFACE_ID "$letterbox" cmux register orphan-agent 2>/dev/null; then
  echo 'FAIL: caller-null registration was accepted' >&2
  exit 1
fi
if [[ -f "$LETTERBOX_CMUX_REGISTRY" ]] && grep -F 'surface:9' "$LETTERBOX_CMUX_REGISTRY" >/dev/null; then
  echo 'FAIL: focused surface registered despite null caller' >&2
  exit 1
fi

printf '%s\n' 'cmux uuid registration test: PASS'

