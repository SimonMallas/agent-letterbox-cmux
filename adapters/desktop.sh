#!/usr/bin/env bash
# Generic macOS activate-and-notify doorbell adapter.
# Configured via LETTERBOX_MACOS_APP (e.g. "Hermes").
# Follows the standard 3-argument letterbox contract.
set -euo pipefail

to="${1:?recipient}"
type="${2:?type}"
slug="${3:?slug}"

app="${LETTERBOX_MACOS_APP:-}"
[[ -n "$app" ]] || { echo 'desktop doorbell deferred: LETTERBOX_MACOS_APP not set' >&2; exit 0; }
command -v osascript >/dev/null 2>&1 || { echo 'desktop doorbell deferred: osascript unavailable' >&2; exit 0; }

message="📬 letterbox doorbell: unacked $type in ${LETTERBOX_DIR:?set LETTERBOX_DIR}/$to/inbox/ — please check"

# Notification (always attempted)
osascript -e "display notification \"$message\" with title \"Letterbox\" subtitle \"$app\"" 2>/dev/null || true

# Activation (best-effort)
osascript -e "tell application \"$app\" to activate" 2>/dev/null || true

echo "desktop notification + activation attempted for $app"
