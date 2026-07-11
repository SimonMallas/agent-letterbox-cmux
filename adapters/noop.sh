#!/usr/bin/env bash
# No-op doorbell adapter. Durable inbox delivery already succeeded.
# Arguments: recipient message-type slug
set -euo pipefail
printf 'doorbell deferred: %s (%s: %s)\n' "$1" "$2" "$3"
