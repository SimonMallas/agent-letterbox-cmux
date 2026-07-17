#!/usr/bin/env bash
# Bootstrap proof: setup creates a portable team config and run self-registers
# an agent in its current cmux surface before launching the command.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
letterbox="$root/bin/letterbox"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin"

cat > "$tmp/bin/cmux" <<'MOCK'
#!/usr/bin/env bash
case "$1" in
  tree) echo 'surface:9 [terminal] "new agent"' ;;
esac
MOCK
chmod +x "$tmp/bin/cmux"

export PATH="$tmp/bin:$PATH"
export XDG_CONFIG_HOME="$tmp/config"
export LETTERBOX_SKILLS_DIR="$tmp/skills"
box="$tmp/team"

"$letterbox" cmux setup --agents sender,receiver --dir "$box" --submit
[[ -f "$box/env.sh" && -f "$box/AGENT-LETTERBOX.md" ]]
[[ -L "$LETTERBOX_SKILLS_DIR/agent-letterbox" ]]
[[ -f "$LETTERBOX_SKILLS_DIR/agent-letterbox/SKILL.md" ]]
[[ -d "$box/sender/inbox" && -d "$box/receiver/processed" ]]
test "$(<"$XDG_CONFIG_HOME/agent-letterbox/default-dir")" = "$box"

CMUX_SURFACE_ID=surface:9 "$letterbox" cmux run receiver -- bash -c '
  printf "%s|%s|%s\n" "$LETTERBOX_AGENT" "$LETTERBOX_DIR" "$LETTERBOX_CMUX_SUBMIT" > "$LETTERBOX_DIR/run-result"
'
test "$(<"$box/run-result")" = "receiver|$box|1"
awk -F $'\t' '$1 == "receiver" && $2 == "surface:9" { found=1 } END { exit !found }' "$box/cmux-agents.tsv"
printf '%s\n' 'cmux setup/run test: PASS'
