#!/usr/bin/env bash
# Generic macOS activate-and-notify doorbell adapter.
# Configured via LETTERBOX_MACOS_APP.
# Uses argv-based AppleScript (no source interpolation).
set -euo pipefail

to="${1:?recipient}"
type="${2:?type}"
slug="${3:?slug}"

app="${LETTERBOX_MACOS_APP:-}"
[[ -n "$app" ]] || { echo 'desktop doorbell deferred: LETTERBOX_MACOS_APP not set' >&2; exit 0; }
command -v osascript >/dev/null 2>&1 || { echo 'desktop doorbell deferred: osascript unavailable' >&2; exit 0; }

message="📬 letterbox doorbell: unacked $type in ${LETTERBOX_DIR:?set LETTERBOX_DIR}/$to/inbox/ — please check"

# Notification via argv
osascript -e 'on run argv
  display notification (item 1 of argv) with title (item 2 of argv) subtitle (item 3 of argv)
end run' "$message" "Letterbox" "$app" 2>/dev/null || true

# Activation via argv
osascript -e 'on run argv
  tell application (item 1 of argv) to activate
end run' "$app" 2>/dev/null || true

echo "desktop notification + activation attempted for $app"
