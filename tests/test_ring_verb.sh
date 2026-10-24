#!/usr/bin/env bash
# Contract for the public integrated Bridge helper: only a matching, durable
# inbox letter may be announced, and the verb emits one v=1 outcome line.
set -euo pipefail

EDITION="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
ROOT="$(mktemp -d /tmp/lb-ring-test.XXXXXX)"
trap 'rm -rf "$ROOT"' EXIT
mkdir -p "$ROOT/box/agent/inbox" "$ROOT/box/agent/processed"

ID="2026-10-24T140000-chat-bridge-info-hello-0a1b2c3d"
printf -- '---\nid: %s\nfrom: chat-bridge\nto: agent\ntype: info\n---\nhello\n' "$ID" > "$ROOT/box/agent/inbox/$ID.md"
cat > "$ROOT/lb" <<SH
#!/usr/bin/env bash
export LETTERBOX_DIR="$ROOT/box"
[[ "${NO_DOORBELL:-}" == 1 ]] || export LETTERBOX_DOORBELL="$EDITION/adapters/noop.sh"
exec "$EDITION/bin/letterbox" "\$@"
SH
chmod +x "$ROOT/lb"

pass=0
ok() { printf 'PASS: %s\n' "$1"; pass=$((pass + 1)); }
bad() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

out="$("$ROOT/lb" ring agent info "$ID")"
[[ "$out" == 'doorbell-outcome v=1 outcome=no_live_surface reason=unconfirmed target=-' ]] \
  || bad "valid letter emits exactly one parsed outcome ($out)"
ok "valid letter emits one outcome"
printf "export LETTERBOX_DIR='%s'\nexport LETTERBOX_DOORBELL='%s/adapters/noop.sh'\n" "$ROOT/box" "$EDITION" > "$ROOT/box/env.sh"
fallback="$(NO_DOORBELL=1 "$ROOT/lb" ring agent info "$ID")"
[[ "$fallback" == 'doorbell-outcome v=1 outcome=no_live_surface reason=unconfirmed target=-' ]] \
  || bad "ring loads the mailbox env when Bridge has no doorbell config ($fallback)"
ok "ring loads mailbox env"

probe="$("$ROOT/lb" ring alb-doctor-probe info 1970-01-01T000000-alb-probe-00000000)"
[[ "$probe" == 'doorbell-outcome v=1 outcome=no_live_surface reason=surface_not_found target=-' ]] \
  || bad "Bridge capability probe emits its required outcome ($probe)"
ok "Bridge capability probe emits one outcome"

refused() {
  local name="$1" out rc=0; shift
  out="$("$ROOT/lb" ring "$@" 2>&1)" || rc=$?
  [[ "$rc" -ne 0 && "$out" != *doorbell-outcome* ]] || bad "$name"
  ok "$name"
}
refused "missing letter is not announced" agent info 2026-10-24T140001-missing-0a1b2c3e
refused "path-shaped id is refused" agent info "../../agent/inbox/$ID"
refused "invalid type is refused" agent bogus "$ID"
refused "path-shaped recipient is refused" 'agent/.' info "$ID"
printf -- '---\nid: %s\nfrom: chat-bridge\nto: other\ntype: info\n---\nx\n' "$ID" > "$ROOT/box/agent/inbox/$ID.md"
refused "mismatched envelope is not announced" agent info "$ID"
X="2026-10-24T140002-chat-bridge-info-symlink-0a1b2c3f"
mkdir -p "$ROOT/outside" "$ROOT/box/sym/processed"
printf -- '---\nid: %s\nfrom: chat-bridge\nto: agent\ntype: info\n---\nx\n' "$X" > "$ROOT/outside/$X.md"
ln -s "$ROOT/outside/$X.md" "$ROOT/box/agent/inbox/$X.md"
refused "symlinked letter is not announced" agent info "$X"
rm -f "$ROOT/box/agent/inbox/$X.md"
printf -- '---\nid: %s\nfrom: chat-bridge\nto: sym\ntype: info\n---\nx\n' "$X" > "$ROOT/outside/$X.md"
ln -s "$ROOT/outside" "$ROOT/box/sym/inbox"
refused "symlinked inbox is not announced" sym info "$X"
usage="$("$ROOT/lb" unknown 2>&1)" || true
[[ "$usage" == *'|ring|'* ]] || bad "usage lists ring"
ok "usage lists ring"
printf -- '---\nid: %s\nfrom: chat-bridge\nto: agent\ntype: info\n---\nhello\n' "$ID" > "$ROOT/box/agent/inbox/$ID.md"

# Smoke the released Bridge parser when its package interpreter is supplied.
if [[ -n "${ALB_PYTHON:-}" ]] && "$ALB_PYTHON" -c 'import alb.bridge.run' 2>/dev/null; then
  ALB_PYTHON="$ALB_PYTHON" "$ALB_PYTHON" -I - "$ROOT/lb" <<'PY' || bad "Bridge parser accepts helper outcome"
import sys
from alb.bridge import run
try:
    run._bus_ring("agent", "info", "2026-10-24T140000-chat-bridge-info-hello-0a1b2c3d", binary=sys.argv[1])
except run.RingNotDelivered as exc:
    assert run._ring_failure_reason(exc) == "unconfirmed"
else:
    raise AssertionError("expected no_live_surface outcome")
PY
  ok "Bridge parser smoke"
else
  printf 'test: SKIP Bridge parser smoke (set ALB_PYTHON)\n'
fi
printf 'ring verb suite: PASS (%s)\n' "$pass"
