#!/usr/bin/env bash
# Dependency-free Bash mock test for the macOS desktop adapter.
set -euo pipefail

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

cat > "$tmpdir/osascript" <<'MOCK'
#!/usr/bin/env bash
printf '%s\n' "$@" >> "$MOCK_LOG"
MOCK
chmod +x "$tmpdir/osascript"

app='Hermes "quoted"'
box='/tmp/letterbox-desktop-test'
export PATH="$tmpdir:$PATH"
export LETTERBOX_MACOS_APP="$app"
export LETTERBOX_DIR="$box"
export MOCK_LOG="$tmpdir/calls.log"

bash "$(dirname "$0")/../adapters/desktop.sh" reviewer delegate test-slug

# Fixed AppleScript source is present, while dynamic values reach osascript as
# separate argv entries instead of being interpolated into that source.
grep -F 'display notification (item 1 of argv)' "$MOCK_LOG" >/dev/null
grep -F 'tell application (item 1 of argv)' "$MOCK_LOG" >/dev/null
grep -Fx "$app" "$MOCK_LOG" >/dev/null
grep -Fx "📬 letterbox doorbell: unacked delegate in $box/reviewer/inbox/ — please check" "$MOCK_LOG" >/dev/null
printf '%s\n' 'desktop adapter test: PASS'
