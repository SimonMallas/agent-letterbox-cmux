#!/usr/bin/env bash
# Dependency-free Bash mock test for the desktop adapter.
set -euo pipefail

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

# Create mock osascript
cat > "$tmpdir/osascript" << 'MOCK'
#!/usr/bin/env bash
echo "MOCK_OSASCRIPT_CALLED: $*" >> "$MOCK_LOG"
exit 0
MOCK
chmod +x "$tmpdir/osascript"

export PATH="$tmpdir:$PATH"
export LETTERBOX_MACOS_APP="Hermes"
export LETTERBOX_DIR="/tmp/letterbox"
export MOCK_LOG="$tmpdir/calls.log"

# Run the adapter
bash "$(dirname "$0")/../adapters/desktop.sh" pi delegate test-slug

# Verify calls
if grep -q "display notification" "$MOCK_LOG" && grep -q "tell application" "$MOCK_LOG"; then
  echo "PASS: osascript was invoked correctly (notification + activation)"
  exit 0
else
  echo "FAIL: expected osascript calls not found"
  cat "$MOCK_LOG"
  exit 1
fi
