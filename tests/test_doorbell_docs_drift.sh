#!/usr/bin/env bash
# Adapter-backed doorbell docs/code drift gate.
# Asks adapters/cmux.sh (never re-implements the line). Every documented
# `📬 letterbox doorbell:` in README/SPEC/skill must match that shape.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"; cd "$root"

plat=""
for c in cmux tmux herdr zellij; do
  if [[ -x "$root/adapters/$c.sh" ]]; then plat="$c"; break; fi
done
adapter="$root/adapters/${plat:-}.sh"
if [[ -z "$plat" || ! -x "$adapter" ]]; then
  echo "FAIL: adapters/<platform>.sh missing — gate would be vacuous" >&2
  exit 1
fi

work="$(mktemp -d "${TMPDIR:-/tmp}/lb-drift.XXXXXX")"
cleanup() { rm -rf "$work"; }
trap cleanup EXIT

# Known invocation values — used only to *normalise* the captured line,
# never to construct the expected doorbell.
inv_dir="$work/box"
inv_to="reviewer"
inv_type="info"
inv_from="relaybot"
mkdir -p "$inv_dir" "$work/bin"

setup_platform() {
  case "$plat" in
    cmux)
      cat > "$work/bin/cmux" <<'MOCK'
#!/usr/bin/env bash
echo "$*" >> "$MOCK_LOG"
case "$1" in
  tree) echo 'surface:1 [terminal] "reviewer - pane"' ;;
esac
exit 0
MOCK
      chmod +x "$work/bin/cmux"
      printf 'reviewer\treviewer\n' > "$work/patterns.tsv"
      ;;
    tmux)
      cat > "$work/bin/tmux" <<'MOCK'
#!/usr/bin/env bash
echo "$*" >> "$MOCK_LOG"
case "$1" in
  list-panes) printf '%s\n' "${MOCK_PANE:-%1}" ;;
  has-session) exit 0 ;;
esac
exit 0
MOCK
      chmod +x "$work/bin/tmux"
      printf 'reviewer\t%%1\n' > "$work/patterns.tsv"
      ;;
    herdr)
      cat > "$work/bin/herdr" <<'MOCK'
#!/usr/bin/env bash
echo "$*" >> "$MOCK_LOG"
exit 0
MOCK
      chmod +x "$work/bin/herdr"
      printf 'reviewer\t%%1\n' > "$work/patterns.tsv"
      ;;
    zellij)
      cat > "$work/bin/zellij" <<'MOCK'
#!/usr/bin/env bash
echo "$*" >> "$MOCK_LOG"
if [[ "${1:-}" == "-s" ]]; then shift 2; fi
if [[ "${1:-}" == "action" && "${2:-}" == "list-panes" ]]; then
  printf 'terminal_7 [Pane #7] running\n'
fi
exit 0
MOCK
      chmod +x "$work/bin/zellij"
      printf 'reviewer\t7\tsess\n' > "$work/patterns.tsv"
      ;;
  esac
}

emit_real() {
  local tok="${1:-}" from="${2:-}" log="$work/send.log"
  : > "$log"
  case "$plat" in
    cmux)
      MOCK_LOG="$log" PATH="$work/bin:$PATH" \
        LETTERBOX_DIR="$inv_dir" LETTERBOX_CMUX_PATTERNS="$work/patterns.tsv" \
        LETTERBOX_CMUX_SUBMIT=1 LETTERBOX_DOORBELL_FROM="$from" \
        "$adapter" "$inv_to" "$inv_type" ${tok:+"$tok"} >/dev/null 2>&1 || true
      sed -n 's/^send --surface surface:[0-9][0-9]* //p' "$log" | head -1
      ;;
    tmux)
      MOCK_LOG="$log" MOCK_PANE='%1' PATH="$work/bin:$PATH" \
        LETTERBOX_DIR="$inv_dir" LETTERBOX_TMUX_PATTERNS="$work/patterns.tsv" \
        LETTERBOX_TMUX_SUBMIT=1 LETTERBOX_DOORBELL_TOKEN="$tok" \
        LETTERBOX_DOORBELL_FROM="$from" \
        "$adapter" "$inv_to" "$inv_type" someslug >/dev/null 2>&1 || true
      sed -n 's/^send-keys -t %1 -l //p' "$log" | head -1
      ;;
    herdr)
      MOCK_LOG="$log" HERDR_BIN_PATH="$work/bin/herdr" \
        LETTERBOX_DIR="$inv_dir" LETTERBOX_HERDR_PATTERNS="$work/patterns.tsv" \
        LETTERBOX_HERDR_SUBMIT=1 LETTERBOX_DOORBELL_FROM="$from" \
        "$adapter" "$inv_to" "$inv_type" someslug ${tok:+"$tok"} >/dev/null 2>&1 || true
      sed -n 's/^pane send-text %1 //p' "$log" | head -1
      ;;
    zellij)
      MOCK_LOG="$log" ZELLIJ_BIN_PATH="$work/bin/zellij" \
        LETTERBOX_DIR="$inv_dir" LETTERBOX_ZELLIJ_PATTERNS="$work/patterns.tsv" \
        LETTERBOX_ZELLIJ_SUBMIT=1 LETTERBOX_DOORBELL_FROM="$from" \
        "$adapter" "$inv_to" "$inv_type" someslug ${tok:+"$tok"} >/dev/null 2>&1 || true
      sed -n 's/.*write-chars --pane-id [^ ]* //p' "$log" | head -1
      ;;
  esac
}

setup_platform

real_v02="$(emit_real)"
real_v03="$(emit_real a1b2c3d4)"
real_v04="$(emit_real '' "$inv_from")"
real_v04t="$(emit_real a1b2c3d4 "$inv_from")"
if [[ -z "$real_v02" || -z "$real_v03" || -z "$real_v04" || -z "$real_v04t" ]]; then
  echo "FAIL: adapter produced no line — gate would be vacuous" >&2
  exit 1
fi

# Shape taken from the adapter output, with this invocation's values slotted.
# v0.3 is captured from the adapter (not v0.2 concatenated with a suffix),
# so moving the token ahead of the tail fails this gate.
slot() {
  local s="$1"
  s="${s//$inv_dir/<DIR>}"
  s="${s//$inv_to/<AGENT>}"
  s="${s/unacked $inv_type /unacked <TYPE> }"
  s="${s//a1b2c3d4/<TOKEN>}"
  s="${s//from $inv_from /from <SENDER> }"
  printf '%s' "$s"
}
canon_v02="$(slot "$real_v02")"
canon_v03="$(slot "$real_v03")"
canon_v04="$(slot "$real_v04")"
canon_v04t="$(slot "$real_v04t")"

# Single canonical grammar — all four adapters are checked against this,
# not against their own source string. A lone product cannot drift.
GRAMMAR_V02='📬 letterbox doorbell: unacked <TYPE> in <DIR>/<AGENT>/inbox/ — please check'
GRAMMAR_V03="$GRAMMAR_V02 · <TOKEN>"
GRAMMAR_V04='📬 letterbox doorbell: unacked <TYPE> from <SENDER> in <DIR>/<AGENT>/inbox/ — please check'
GRAMMAR_V04T="$GRAMMAR_V04 · <TOKEN>"
if [[ "$canon_v02" != "$GRAMMAR_V02" ]]; then
  echo "FAIL: $plat runtime v0.2 does not match the shared grammar" >&2
  echo "  runtime:  $canon_v02" >&2
  echo "  grammar:  $GRAMMAR_V02" >&2
  exit 1
fi
if [[ "$canon_v03" != "$GRAMMAR_V03" ]]; then
  echo "FAIL: $plat runtime v0.3 does not match the shared grammar" >&2
  echo "  runtime:  $canon_v03" >&2
  echo "  grammar:  $GRAMMAR_V03" >&2
  exit 1
fi
if [[ "$canon_v04" != "$GRAMMAR_V04" ]]; then
  echo "FAIL: $plat runtime v0.4 does not match the shared grammar" >&2
  echo "  runtime:  $canon_v04" >&2
  echo "  grammar:  $GRAMMAR_V04" >&2
  exit 1
fi
if [[ "$canon_v04t" != "$GRAMMAR_V04T" ]]; then
  echo "FAIL: $plat runtime v0.4+token does not match the shared grammar" >&2
  echo "  runtime:  $canon_v04t" >&2
  echo "  grammar:  $GRAMMAR_V04T" >&2
  exit 1
fi
echo "PASS: $plat runtime matches the shared v0.2/v0.3/v0.4 grammar"

# Docs-followable rule (what the corrected docs teach): prefix match,
# optional ' · <8hex>' after the tail, optional safe ' from <sender>'
# middle insert, reject malformed / the short line.
docs_rule_accept() {
  local line="$1" rest mid sender
  local prefix='📬 letterbox doorbell: unacked '
  local tail=' — please check'
  [[ "$line" == "$prefix"* ]] || return 1
  [[ "$line" == *"$tail"* ]] || return 1
  rest="${line#*"$tail"}"
  if [[ -n "$rest" && ! "$rest" =~ ^\ ·\ [0-9a-f]{8}$ ]]; then return 1; fi
  mid="${line#"$prefix"}"
  mid="${mid%%"$tail"*}"
  if [[ "$mid" == *" from "* ]]; then
    sender="${mid#*" from "}"
    sender="${sender%%" in "*}"
    [[ "$sender" =~ ^[A-Za-z][A-Za-z0-9._-]{0,31}$ ]] || return 1
  fi
  return 0
}
if ! docs_rule_accept "$real_v02"; then
  echo "FAIL: documented prefix rule rejects runtime v0.2" >&2
  exit 1
fi
if ! docs_rule_accept "$real_v03"; then
  echo "FAIL: documented prefix rule rejects runtime v0.3" >&2
  exit 1
fi
if ! docs_rule_accept "$real_v04"; then
  echo "FAIL: documented prefix rule rejects runtime v0.4" >&2
  exit 1
fi
if ! docs_rule_accept "$real_v04t"; then
  echo "FAIL: documented prefix rule rejects runtime v0.4+token" >&2
  exit 1
fi
if docs_rule_accept "$real_v02 · zzzzzzzz"; then
  echo "FAIL: documented prefix rule accepted a malformed suffix" >&2
  exit 1
fi
if docs_rule_accept '📬 letterbox doorbell: check your inbox'; then
  echo "FAIL: documented prefix rule accepted the short README line" >&2
  exit 1
fi
if docs_rule_accept '📬 letterbox doorbell: unacked info from - in x/agent/inbox/ — please check'; then
  echo "FAIL: documented prefix rule accepted a from-dash sender" >&2
  exit 1
fi
if docs_rule_accept '📬 letterbox doorbell: unacked info from ../etc in x/agent/inbox/ — please check'; then
  echo "FAIL: documented prefix rule accepted a path-shaped sender" >&2
  exit 1
fi
echo "PASS: documented prefix rule accepts all runtime shapes and rejects malformed"

normalize_doc() {
  local s="$1"
  s="${s#*\`}"
  s="${s%%\`*}"
  if [[ "$s" != *'📬 letterbox doorbell:'* ]]; then
    printf '%s\n' "$s"
    return 0
  fi
  s="${s#*📬 letterbox doorbell:}"
  s="📬 letterbox doorbell:$s"
  s="${s%%$'\n'*}"
  s="${s%"${s##*[![:space:]]}"}"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s//“/}"
  s="${s//”/}"
  s="${s%\"}"
  s="${s%\'}"
  s="${s//<8-lowercase-hex>/<TOKEN>}"
  s="${s//<8-hex>/<TOKEN>}"
  s="${s//<8hex>/<TOKEN>}"
  if [[ "$s" =~ \ ·\ [0-9a-f]{8}$ ]]; then
    s="${s% · *} · <TOKEN>"
  fi
  s="${s//<type>/<TYPE>}"
  s="${s//<agent>/<AGENT>}"
  s="${s//<sender>/<SENDER>}"
  s="${s//<letterbox>/<DIR>}"
  s="${s//<LETTERBOX_DIR>/<DIR>}"
  s="${s//\$type/<TYPE>}"
  s="${s//\$to/<AGENT>}"
  s="${s//\${line_from\}/<SENDER>}"
  s="${s//\$line_from/<SENDER>}"
  s="${s//\$from/<SENDER>}"
  s="${s//\$tok/<TOKEN>}"
  s="${s//\$token/<TOKEN>}"
  s="${s//\${tok\}/<TOKEN>}"
  s="${s//\${token\}/<TOKEN>}"
  s="${s//\${root\}/<DIR>}"
  s="${s//\${LETTERBOX_DIR:?set LETTERBOX_DIR\}/<DIR>}"
  s="${s//\${LETTERBOX_DIR\}/<DIR>}"
  s="$(printf '%s' "$s" | sed -E \
    -e 's/unacked [^ ]+ in /unacked <TYPE> in /' \
    -e 's# in [^[:space:]]+/[^[:space:]]+/inbox/# in <DIR>/<AGENT>/inbox/#')"
  printf '%s\n' "$s"
}

shape_ok() {
  local n="$1"
  [[ "$n" == "$canon_v02" || "$n" == "$canon_v03" || "$n" == "$canon_v04" || "$n" == "$canon_v04t" ]] && return 0
  # Prefix fragments (skill "MUST start with …") are allowed if they are a
  # real prefix of the adapter shape — not a different sentence.
  [[ -n "$n" && "$canon_v02" == "$n"* ]] && return 0
  [[ -n "$n" && "$canon_v03" == "$n"* ]] && return 0
  [[ -n "$n" && "$canon_v04" == "$n"* ]] && return 0
  [[ -n "$n" && "$canon_v04t" == "$n"* ]] && return 0
  return 1
}

fails=0
scan_file() {
  local f="$1" num line payload norm
  [[ -f "$f" ]] || return 0
  num=0
  while IFS= read -r line || [[ -n "$line" ]]; do
    num=$((num + 1))
    [[ "$line" == *'📬 letterbox doorbell:'* ]] || continue
    payload="$(normalize_doc "$line")"
    if shape_ok "$payload"; then
      echo "PASS: $f:$num matches adapter shape"
    else
      echo "FAIL: doorbell docs/code drift at $f:$num" >&2
      echo "  documented: $payload" >&2
      echo "  adapter v0.2: $canon_v02" >&2
      echo "  adapter v0.3: $canon_v03" >&2
      echo "  adapter v0.4: $canon_v04" >&2
      echo "  adapter v0.4+token: $canon_v04t" >&2
      fails=$((fails + 1))
    fi
  done < "$f"
}

# Every tracked file (not a path allowlist). The gate and its mutation
# harness necessarily contain the short line as a negative plant/check.
# conformance/ holds canonical grammar fixture DATA (not docs); it is
# covered by its own conformance tests, not by this drift scan.
skip_scan() {
  case "$1" in
    tests/test_doorbell_docs_drift.sh|tests/test_doorbell_docs_drift_mutation.sh) return 0;;
    conformance/*) return 0;;
  esac
  return 1
}
list_files() {
  if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    git ls-files -z
  else
    find . -type f -not -path './.git/*' -print0
  fi
}
while IFS= read -r -d '' f; do
  f="${f#./}"
  skip_scan "$f" && continue
  [[ -f "$f" ]] || continue
  grep -qI '' "$f" 2>/dev/null || continue
  scan_file "$f"
done < <(list_files)

if (( fails > 0 )); then
  echo "doorbell-docs-drift: FAIL ($fails)" >&2
  exit 1
fi
echo "doorbell-docs-drift: PASS"
exit 0
