#!/usr/bin/env bash
# The installer is both the first install and the update. An update must say it
# updated and must not print the first-time team setup: that setup is shared,
# and an agent updating itself had to work out not to run it (26 Oct).
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
git clone -q "$root" "$tmp/source"
export AGENT_LETTERBOX_REPO="$tmp/source"
export AGENT_LETTERBOX_INSTALL_DIR="$tmp/install"
export AGENT_LETTERBOX_BIN_DIR="$tmp/bin"

first="$(bash "$root/install.sh" 2>&1)"
[[ "$first" == *"Installed Agent Letterbox for cmux."* && "$first" == *"letterbox cmux setup --agents"* ]] \
  || { printf 'FAIL: a first install gives the setup command:\n%s\n' "$first" >&2; exit 1; }

again="$(bash "$root/install.sh" 2>&1)"
version="$(<"$tmp/install/VERSION")"
[[ "$again" == *"Updated Agent Letterbox for cmux to $version."* ]] \
  || { printf 'FAIL: an update says it updated:\n%s\n' "$again" >&2; exit 1; }
[[ "$again" != *"setup --agents"* ]] \
  || { printf 'FAIL: an update prints the first-time setup:\n%s\n' "$again" >&2; exit 1; }

printf '%s\n' 'install update suite: PASS'
