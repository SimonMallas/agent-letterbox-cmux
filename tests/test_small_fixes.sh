#!/usr/bin/env bash
# Regressions for small defects, each reproduced on 0.7.0 before its fix.
set -uo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
letterbox="$root/bin/letterbox"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/home"

cat > "$tmp/bin/cmux" <<'MOCK'
#!/usr/bin/env bash
case "$1" in
  tree) [[ "${CMUX_TREE_FAILS:-}" == 1 ]] && exit 1; echo 'surface:12 [terminal] "agent"' ;;
esac
MOCK
chmod +x "$tmp/bin/cmux"
export PATH="$tmp/bin:$PATH" HOME="$tmp/home" XDG_CONFIG_HOME="$tmp/home/.config"
export LETTERBOX_DIR="$tmp/box" LETTERBOX_CMUX_REGISTRY="$tmp/box/cmux-agents.tsv"
unset LETTERBOX_DOORBELL LETTERBOX_AGENT LETTERBOX_CHECK_STALE_DAYS LETTERBOX_CHECK_TIDY_AT LETTERBOX_NOTES_DIR LETTERBOX_SESSION

fails=0
ok() { printf 'PASS: %s\n' "$1"; }
bad() { printf 'FAIL: %s\n' "$1" >&2; fails=$((fails + 1)); }

"$letterbox" init alpha beta >/dev/null
sent="$(printf 'please\n' | LETTERBOX_AGENT=alpha "$letterbox" send beta request job --ack)"
id="$(basename "${sent##* }" .md)"
tok="${id##*-}"
[[ -n "$id" && -n "$tok" ]] || { echo "FAIL: setup (id=$id tok=$tok)" >&2; exit 1; }

# 1. One malformed letter in any mailbox must not silence `token`.
printf 'no frontmatter here\n' > "$tmp/box/alpha/inbox/junk.md"
out="$(LETTERBOX_AGENT=beta "$letterbox" token "$tok" 2>&1)"
[[ "$out" == unhandled* ]] && ok "token skips a malformed letter" || bad "token with a malformed letter elsewhere: '$out'"
rm "$tmp/box/alpha/inbox/junk.md"

# 2. A stale-days value that is not a plain number falls back, it does not abort check.
for days in 08 1.5 abc ''; do
  out="$(LETTERBOX_AGENT=beta LETTERBOX_CHECK_STALE_DAYS="$days" "$letterbox" check 2>&1)" && [[ "$out" == *"$tok"* ]] \
    && ok "check with LETTERBOX_CHECK_STALE_DAYS='$days'" || bad "check with LETTERBOX_CHECK_STALE_DAYS='$days': $out"
done

# 3. A progress note is another agent's text: no control bytes reach the terminal.
printf 'ok\n' | LETTERBOX_AGENT=beta "$letterbox" reply "$id" ack taking >/dev/null
LETTERBOX_AGENT=beta "$letterbox" progress "$id" "$(printf 'half\033[2Jdone\302\233x')" >/dev/null
out="$(LETTERBOX_AGENT=beta "$letterbox" check)"
[[ "$out" == *"progress: half[2Jdonex"* && "$out" != *$'\033'* && "$out" != *$'\302\233'* ]] \
  && ok "progress note printed without control bytes" || bad "progress note carries control bytes"

# 4. A dangling symlink is skipped; the letters after it are still shown.
ln -s "$tmp/nowhere.md" "$tmp/box/beta/inbox/0000-dangling.md"
out="$(LETTERBOX_AGENT=beta "$letterbox" check)"
[[ "$out" == *"$tok"* ]] && ok "check reads past a dangling symlink" || bad "check stopped at a dangling symlink"
rm "$tmp/box/beta/inbox/0000-dangling.md"

# 5. Registration liveness is an exact surface match, not a substring.
if CMUX_SURFACE_ID=surface:1 "$letterbox" cmux register ghost >/dev/null 2>&1; then
  bad "surface:1 registered while only surface:12 is live"
else ok "a surface that is only a prefix of a live one is refused"; fi

# 6. A failed cmux lookup during setup leaves the registrations alone.
CMUX_SURFACE_ID=surface:12 "$letterbox" cmux register alpha >/dev/null
CMUX_TREE_FAILS=1 "$letterbox" cmux setup --dir "$tmp/box" --agents alpha,beta >/dev/null 2>&1
grep -q "^alpha	surface:12	" "$LETTERBOX_CMUX_REGISTRY" \
  && ok "failed cmux tree keeps registrations" || bad "failed cmux tree emptied the registry"

# 7. A relative --dir is stored as an absolute path.
(cd "$tmp" && env -u LETTERBOX_DIR -u LETTERBOX_CMUX_REGISTRY "$letterbox" cmux setup --dir ./relbox --agents r1 >/dev/null 2>&1)
want="$tmp/relbox"
[[ "$(cat "$XDG_CONFIG_HOME/agent-letterbox/default-dir" 2>/dev/null)" == "$want" ]] \
  && grep -qF "export LETTERBOX_DIR='$want'" "$tmp/relbox/env.sh" \
  && ok "relative --dir stored absolute" || bad "relative --dir stored as typed"

# 8. CDPATH must not redirect a bare relative --dir to some other directory.
mkdir -p "$tmp/decoy/team" "$tmp/work"
(cd "$tmp/work" && CDPATH="$tmp/decoy" env -u LETTERBOX_DIR -u LETTERBOX_CMUX_REGISTRY "$letterbox" cmux setup --dir team --agents c1 >/dev/null 2>&1)
[[ "$(cat "$XDG_CONFIG_HOME/agent-letterbox/default-dir" 2>/dev/null)" == "$tmp/work/team" && -d "$tmp/work/team/c1/inbox" ]] \
  && ok "CDPATH does not redirect --dir" || bad "CDPATH redirected --dir: $(cat "$XDG_CONFIG_HOME/agent-letterbox/default-dir" 2>/dev/null | tr '\n' '|')"

# 9. A doorbell assigned without 'export' in env.sh still counts as set up.
mkdir -p "$tmp/plain/p1/inbox" "$tmp/plain/p1/processed"
printf "LETTERBOX_DOORBELL='%s/adapters/noop.sh'\n" "$root" > "$tmp/plain/env.sh"
out="$(LETTERBOX_DIR="$tmp/plain" LETTERBOX_AGENT=p1 "$letterbox" check 2>&1)"
[[ "$out" != *"doorbell: not set up"* ]] && ok "unexported doorbell line is not a false warning" || bad "false 'not set up' for an unexported doorbell line"

[[ "$fails" -eq 0 ]] || exit 1
echo 'small fixes: PASS'
