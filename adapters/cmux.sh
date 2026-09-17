#!/usr/bin/env bash
# cmux doorbell adapter — doorbell-outcome v=1 emitter.
# The letter is already durable; this rings a live surface and reports ONE
# machine-readable outcome line on stdout (the wrapper owns forwarding).
# Prefer self-registered live surfaces in LETTERBOX_CMUX_REGISTRY; fall back to
# LETTERBOX_CMUX_PATTERNS (agent<TAB>title-substring) for legacy/static agents.
set -uo pipefail

to="${1:?recipient}"
type="${2:?type}"
token="${3:-}"

# doorbell-outcome v=1: exactly one line, validated before printing.
# outcome ∈ {submitted, pasted_not_submitted, no_live_surface}; reason/target
# cross-checked per the contract (no_live_surface always target=-; submitted
# and pasted always target=<pinned pane>, reason=- or enter_failed|-).
emit_outcome() { # $1=outcome $2=reason $3=target
    local outcome="$1" reason="$2" target="$3"
    case "$outcome" in
        submitted)
            [[ "$reason" == "-" && "$target" != "-" ]] || return 1
            [[ "$target" =~ ^[A-Za-z0-9._:+-]+$ || "$target" =~ ^%[0-9]+$ ]] || return 1
            ;;
        pasted_not_submitted)
            case "$reason" in enter_failed|-) ;; *) return 1;; esac
            [[ "$target" != "-" ]] || return 1
            [[ "$target" =~ ^[A-Za-z0-9._:+-]+$ || "$target" =~ ^%[0-9]+$ ]] || return 1
            ;;
        no_live_surface)
            [[ "$reason" != "-" && "$reason" =~ ^[A-Za-z0-9._:+-]+$ ]] || return 1
            [[ "$target" == "-" ]] || return 1
            ;;
        *) return 1;;
    esac
    printf 'doorbell-outcome v=1 outcome=%s reason=%s target=%s\n' \
        "$outcome" "$reason" "$target"
}

# Bounded call: 124 = actual timeout (runner-killed; the sentinel is
# runner-owned — a child exiting 124 itself is remapped to 123), 125 = runner
# (python3) unavailable, 127 = missing binary, else the child's exit code.
# Runner presence is verified up front, so a 124 at a classification point
# is always a genuine timeout — never ambiguous.
bounded_cmd() { # $1=seconds, rest=argv
    local secs="$1"; shift
    command -v python3 >/dev/null 2>&1 || return 125
    python3 -c '
import os, signal, subprocess, sys
try:
    p = subprocess.Popen(sys.argv[2:], start_new_session=True)
except FileNotFoundError:
    sys.exit(127)
try:
    rc = p.wait(timeout=float(sys.argv[1]))
except subprocess.TimeoutExpired:
    try:
        os.killpg(p.pid, signal.SIGKILL)
    except Exception:
        p.kill()
    p.wait()
    sys.exit(124)
# The runner owns the 124 sentinel: a child that exits 124 on its own was
# NOT killed on timeout and must not be read as one — remap to 123.
sys.exit(123 if rc == 124 else rc)
' "$secs" "$@"
}

command -v cmux >/dev/null 2>&1 || { emit_outcome no_live_surface adapter_unavailable -; exit 0; }
# Runner presence is verified BEFORE any 124 is read as a timeout: a missing
# python3 is adapter_unavailable (non-retryable), never helper_timeout.
command -v python3 >/dev/null 2>&1 || { emit_outcome no_live_surface adapter_unavailable -; exit 0; }

# Ruling 5 middle insert: name the durable letter's sender, but only when the
# wrapper supplied a value that passes the safe-identifier regex (re-checked
# here — env is never trusted). Otherwise the line stays the old shape.
from="${LETTERBOX_DOORBELL_FROM:-}"
if [[ "$from" =~ ^[A-Za-z][A-Za-z0-9._-]{0,31}$ ]]; then
  line="📬 letterbox doorbell: unacked $type from $from in ${LETTERBOX_DIR:?set LETTERBOX_DIR}/$to/inbox/ — please check"
else
  line="📬 letterbox doorbell: unacked $type in ${LETTERBOX_DIR:?set LETTERBOX_DIR}/$to/inbox/ — please check"
fi
if [[ "$token" =~ ^[0-9a-f]{8}$ ]]; then
  line="$line · $token"
fi
registry="${LETTERBOX_CMUX_REGISTRY:-$LETTERBOX_DIR/cmux-agents.tsv}"
bound_s="${LETTERBOX_DOORBELL_TIMEOUT:-1}"
tree_ec=0
tree="$(bounded_cmd "$bound_s" cmux tree --all 2>/dev/null)" || tree_ec=$?
if [[ "$tree_ec" -eq 124 ]]; then
  # Lookup hung before any doorbell bytes were attempted: the contract's only
  # retryable class (proven pre-inject timeout).
  emit_outcome no_live_surface helper_timeout -
  exit 0
fi
surface=''

if [[ -f "$registry" ]]; then
  registered="$(awk -F $'\t' -v agent="$to" '$1 == agent { print $2; exit }' "$registry")"
  if [[ "$registered" =~ ^surface:[0-9]+$ ]] && printf '%s\n' "$tree" | grep -E "${registered}([^0-9]|$)" >/dev/null; then
    surface="$registered"
  fi
fi

if [[ -z "$surface" ]]; then
  patterns_file="${LETTERBOX_CMUX_PATTERNS:-}"
  if [[ -n "$patterns_file" && -r "$patterns_file" ]]; then
    while IFS=$'\t' read -r agent pattern; do
      [[ "$agent" == "$to" && -n "$pattern" ]] || continue
      match="$(printf '%s\n' "$tree" | grep -iF -- "$pattern" | grep -o 'surface:[0-9][0-9]*' | head -1 || true)"
      [[ -n "$match" ]] && { surface="$match"; break; }
    done < "$patterns_file"
  fi
fi

[[ -n "$surface" ]] || { emit_outcome no_live_surface surface_not_found -; exit 0; }
notify_body="$type"
[[ "$token" =~ ^[0-9a-f]{8}$ ]] && notify_body="$type · $token"
# Best-effort human ping, bounded like every other step: a hung notify must
# never hold the adapter (and the outcome line) hostage.
bounded_cmd "$bound_s" cmux notify --title "letterbox → $to" --body "$notify_body" >/dev/null 2>&1 || true

# Sending terminal input is explicit opt-in: Enter can submit unrelated text
# already typed in the target pane.
if [[ "${LETTERBOX_CMUX_SUBMIT:-0}" == 1 ]]; then
  send_ec=0
  bounded_cmd "$bound_s" cmux send --surface "$surface" "$line" || send_ec=$?
  if [[ "$send_ec" -ne 0 ]]; then
    if [[ "$send_ec" -eq 124 ]]; then
      # Text step started; bytes may or may not have been injected.
      emit_outcome no_live_surface unconfirmed -
    else
      emit_outcome no_live_surface send_failed -
    fi
    exit 0
  fi
  enter_ec=0
  bounded_cmd "$bound_s" cmux send-key --surface "$surface" Enter || enter_ec=$?
  if [[ "$enter_ec" -ne 0 ]]; then
    if [[ "$enter_ec" -eq 124 ]]; then
      # Enter may have landed after text was confirmed sent.
      emit_outcome no_live_surface unconfirmed -
    else
      emit_outcome pasted_not_submitted enter_failed "$surface"
    fi
    exit 0
  fi
  emit_outcome submitted - "$surface"
else
  emit_outcome no_live_surface notify_only -
fi
