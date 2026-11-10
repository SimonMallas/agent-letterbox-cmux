#!/usr/bin/env bash
# The doorbell must not be lost without anyone being told. Four cases, each
# reproduced on 0.7.0 before its fix.
set -uo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
letterbox="$root/bin/letterbox"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/home"
real_path="$PATH"

cat > "$tmp/bin/cmux" <<'MOCK'
#!/usr/bin/env bash
case "$1" in
  tree) for n in 1 2 3 4 5 6 7 8; do echo "surface:$n [terminal] \"agent\""; done ;;
esac
MOCK
# A doorbell that records each ring and answers with a valid outcome line.
cat > "$tmp/bell.sh" <<BELL
#!/usr/bin/env bash
printf '%s\n' "\$1 \$2" >> "$tmp/rings.log"
echo 'doorbell-outcome v=1 outcome=submitted reason=- target=surface:1'
BELL
chmod +x "$tmp/bin/cmux" "$tmp/bell.sh"
export PATH="$tmp/bin:$PATH" HOME="$tmp/home" XDG_CONFIG_HOME="$tmp/home/.config"
export LETTERBOX_DIR="$tmp/box" LETTERBOX_CMUX_REGISTRY="$tmp/box/cmux-agents.tsv"
unset LETTERBOX_DOORBELL LETTERBOX_AGENT LETTERBOX_CHECK_TIDY_AT LETTERBOX_NOTES_DIR LETTERBOX_SESSION

fails=0
ok() { printf 'PASS: %s\n' "$1"; }
bad() { printf 'FAIL: %s\n' "$1" >&2; fails=$((fails + 1)); }
rings() { [[ -f "$tmp/rings.log" ]] && wc -l < "$tmp/rings.log" | tr -d ' ' || echo 0; }

"$letterbox" init alpha beta >/dev/null

# 1. Nothing configured: the agent is told its bell cannot ring.
out="$(LETTERBOX_AGENT=beta "$letterbox" check 2>&1)"
[[ "$out" == *"doorbell: not set up"* ]] && ok "check says when no doorbell is set up" || bad "check is silent about a missing doorbell: $out"

# 2. The box has settings but this shell never loaded them (an agent not
#    started by `cmux run`): send, reply and nudge still ring.
printf "export LETTERBOX_DIR='%s'\nexport LETTERBOX_DOORBELL='%s'\n" "$tmp/box" "$tmp/bell.sh" > "$tmp/box/env.sh"
out="$(LETTERBOX_AGENT=beta "$letterbox" check 2>&1)"
[[ "$out" != *"doorbell: not set up"* ]] && ok "no warning once the box has a doorbell" || bad "warning shown although the box has a doorbell"
sent="$(printf 'please\n' | LETTERBOX_AGENT=alpha "$letterbox" send beta request job --ack --now)"
[[ "$sent" == *"outcome=submitted"* && "$(rings)" == 1 ]] && ok "send --now rings from the box settings" || bad "send --now did not ring: $sent"
id="$(basename "$(printf '%s\n' "$sent" | grep -m1 '\.md$' | sed 's/^sent: //')" .md)"
out="$(LETTERBOX_AGENT=alpha "$letterbox" nudge "$id" 2>&1)"
[[ "$out" == *"outcome=submitted"* && "$(rings)" == 2 ]] && ok "nudge rings from the box settings" || bad "nudge did not ring: $out"
out="$(printf 'on it\n' | LETTERBOX_AGENT=beta "$letterbox" reply "$id" ack taking --now 2>&1)"
[[ "$out" == *"outcome=submitted"* && "$(rings)" == 3 ]] && ok "reply --now rings from the box settings" || bad "reply --now did not ring: $out"

# 3. A --now reply that dies after the reply is written and before the bell:
#    the retry must ring. (mv fails once, which ends the helper before its ring.)
cat > "$tmp/bin/mv" <<SHIM
#!/usr/bin/env bash
if [[ ! -f "$tmp/mv-failed" ]]; then : > "$tmp/mv-failed"; exit 1; fi
exec /bin/mv "\$@"
SHIM
chmod +x "$tmp/bin/mv"
before="$(rings)"
printf 'done\n' | LETTERBOX_AGENT=beta "$letterbox" reply "$id" result finished --now >/dev/null 2>&1
[[ -f "$tmp/mv-failed" && "$(rings)" == "$before" ]] || bad "crash set-up: the first attempt was meant to die before its ring"
ls "$tmp/box/alpha/inbox" | grep -q -- '--beta--result.md$' || bad "crash set-up: the reply should already be written"
out="$(printf 'done\n' | LETTERBOX_AGENT=beta "$letterbox" reply "$id" result finished --now 2>&1)"
[[ "$(rings)" == $((before + 1)) ]] && ok "retry of a crashed --now reply rings" || bad "retry of a crashed --now reply stayed silent: $out"
# ... and once the task is filed and the reply still unread, a further retry rings too.
out="$(printf 'done\n' | LETTERBOX_AGENT=beta "$letterbox" reply "$id" result finished --now 2>&1)"
[[ "$out" == *"already closed"* && "$(rings)" == $((before + 2)) ]] && ok "retry after filing rings while the reply is unread" || bad "retry after filing stayed silent: $out"
# ... but never after the sender has filed the reply.
r="$(ls "$tmp/box/alpha/inbox" | grep -- '--beta--result.md$')"
LETTERBOX_AGENT=alpha "$letterbox" file "${r%.md}" >/dev/null 2>&1
printf 'done\n' | LETTERBOX_AGENT=beta "$letterbox" reply "$id" result finished --now >/dev/null 2>&1
[[ "$(rings)" == $((before + 2)) ]] && ok "no ring for a reply the sender has filed" || bad "rang for a reply already filed"
rm -f "$tmp/bin/mv"

# 4. Agents registering at the same moment all keep their registration.
for round in 1 2 3; do
  : > "$LETTERBOX_CMUX_REGISTRY"
  for n in 1 2 3 4 5 6 7 8; do
    CMUX_SURFACE_ID="surface:$n" "$letterbox" cmux register "agent$n" >/dev/null 2>&1 &
  done
  wait
  rows="$(wc -l < "$LETTERBOX_CMUX_REGISTRY" | tr -d ' ')"
  [[ "$rows" == 8 ]] || { bad "8 agents registered at once, $rows kept (round $round)"; break; }
done
[[ "$rows" == 8 ]] && ok "8 simultaneous registrations all kept (3 rounds)"

# 6. Every letter rings: a send or reply without --now rings too.
printf "export LETTERBOX_DIR='%s'\nexport LETTERBOX_DOORBELL='%s'\n" "$tmp/box" "$tmp/bell.sh" > "$tmp/box/env.sh"
before="$(rings)"
sent="$(printf 'plain\n' | LETTERBOX_AGENT=alpha "$letterbox" send beta request plain --ack 2>&1)"
[[ "$sent" == *"outcome=submitted"* && "$(rings)" == $((before + 1)) ]] && ok "a send without --now rings" || bad "a send without --now did not ring: $sent"
pid="$(basename "$(printf '%s\n' "$sent" | grep -m1 '\.md$' | sed 's/^sent: //')" .md)"
out="$(printf 'taking it\n' | LETTERBOX_AGENT=beta "$letterbox" reply "$pid" ack plain-ack 2>&1)"
[[ "$out" == *"outcome=submitted"* && "$(rings)" == $((before + 2)) ]] && ok "a reply without --now rings" || bad "a reply without --now did not ring: $out"
out="$(printf 'done\n' | LETTERBOX_AGENT=beta "$letterbox" reply "$pid" result plain-done 2>&1)"
[[ "$out" == *"outcome=submitted"* && "$(rings)" == $((before + 3)) ]] && ok "a result without --now rings" || bad "a result without --now did not ring: $out"

# 5. The cmux adapter types the doorbell when nothing says otherwise: an
#    env.sh written before typing became the default has no SUBMIT line.
cat > "$tmp/bin/cmux" <<'MOCK2'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$CMUX_CALLS"
case "$1" in
  tree) echo 'surface:3 [terminal] "agent"' ;;
esac
MOCK2
chmod +x "$tmp/bin/cmux"
export CMUX_CALLS="$tmp/cmux-calls.log"
printf 'beta\tsurface:3\t2026-01-01T00:00:00Z\n' > "$LETTERBOX_CMUX_REGISTRY"
printf "export LETTERBOX_DIR='%s'\nexport LETTERBOX_DOORBELL='%s/adapters/cmux.sh'\nexport LETTERBOX_CMUX_REGISTRY='%s'\n" "$tmp/box" "$root" "$LETTERBOX_CMUX_REGISTRY" > "$tmp/box/env.sh"
: > "$CMUX_CALLS"
out="$(printf 'wake up\n' | LETTERBOX_AGENT=alpha LETTERBOX_DOORBELL_ENTER_DELAY=0 "$letterbox" send beta info wake --now 2>&1)"
[[ "$out" == *"outcome=submitted"* ]] && grep -q '^send-key --surface surface:3 Enter' "$CMUX_CALLS" \
  && ok "an old env.sh with no SUBMIT line types the doorbell" || bad "no typing by default: $out"
: > "$CMUX_CALLS"
out="$(printf 'quiet\n' | LETTERBOX_AGENT=alpha LETTERBOX_DOORBELL_ENTER_DELAY=0 LETTERBOX_CMUX_SUBMIT=0 "$letterbox" send beta info quiet --now 2>&1)"
[[ "$out" == *"notify_only"* ]] && ! grep -q '^send' "$CMUX_CALLS" \
  && ok "LETTERBOX_CMUX_SUBMIT=0 still stops typing" || bad "SUBMIT=0 did not stop typing: $out"

[[ "$fails" -eq 0 ]] || exit 1
echo 'bell reaches: PASS'
