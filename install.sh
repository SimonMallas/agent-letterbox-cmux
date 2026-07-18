#!/usr/bin/env bash
# Agent Letterbox for cmux installer.
set -euo pipefail

repo="${AGENT_LETTERBOX_REPO:-https://github.com/SimonMallas/agent-letterbox-cmux.git}"
install_dir="${AGENT_LETTERBOX_INSTALL_DIR:-$HOME/.local/share/agent-letterbox-cmux}"
bin_dir="${AGENT_LETTERBOX_BIN_DIR:-$HOME/.local/bin}"

fail() { printf 'agent-letterbox-cmux installer: %s\n' "$*" >&2; exit 1; }
command -v git >/dev/null 2>&1 || fail 'Git is required. Install Git, then run this command again.'

if [[ -e "$install_dir" && ! -d "$install_dir/.git" ]]; then
  fail "$install_dir exists but is not an Agent Letterbox Git checkout"
fi

if [[ -d "$install_dir/.git" ]]; then
  printf 'Updating Agent Letterbox for cmux in %s\n' "$install_dir"
  git -C "$install_dir" pull --ff-only
else
  printf 'Downloading Agent Letterbox for cmux...\n'
  mkdir -p "$(dirname "$install_dir")"
  git clone --depth 1 "$repo" "$install_dir"
fi

mkdir -p "$bin_dir"
launcher="$bin_dir/letterbox"
target="$install_dir/bin/letterbox"
if [[ -e "$launcher" || -L "$launcher" ]]; then
  if [[ -L "$launcher" && "$(readlink "$launcher")" == "$target" ]]; then
    : # Already linked to this installation.
  else
    fail "$launcher already exists. Choose one Letterbox platform, or set AGENT_LETTERBOX_BIN_DIR."
  fi
else
  ln -s "$target" "$launcher"
fi
chmod +x "$install_dir/bin/letterbox" "$install_dir/adapters"/*.sh "$install_dir/tests"/*.sh

printf '\nInstalled Agent Letterbox for cmux.\n'
printf 'Next run:\n\n'
printf '  letterbox cmux setup --agents pi,claude,grok,hermes --automatic-doorbells\n\n'
printf 'If `letterbox` is not found, add %s to your PATH.\n' "$bin_dir"
