#!/usr/bin/env bash
# Adapter-backed doorbell docs/code drift gate.
# Asks adapters/cmux.sh (never re-implements the line). Every documented
# `📬 letterbox doorbell:` in README/SPEC/skill must match that shape.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"; cd "$root"
adapter="$root/adapters/cmux.sh"

if [[ ! -x "$adapter" ]]; then
  echo "FAIL: adapters/cmux.sh missing — gate would be vacuous" >&2
  exit 1
fi

work="$(mktemp -d "${TMPDIR:-/tmp}/lb-drift.XXXXXX")"
cleanup() { rm -rf "$work"; }
trap cleanup EXIT

mockbin="$work/bin"
mkdir -p "$mockbin"
cat > "$mockbin/cmux" <<'MOCK'
#!/usr/bin/env bash
echo "$*" >> "$MOCK_LOG"
case "$1" in
  tree) echo 'surface:1 [terminal] "reviewer - pane"' ;;
  *) : ;;
esac
exit 0
MOCK
chmod +x "$mockbin/cmux"
printf 'reviewer\treviewer\n' > "$work/cmux-patterns.tsv"

# Known invocation values — used only to *normalise* the captured line,
# never to construct the expected doorbell.
inv_dir="$work/box"
inv_to="reviewer"
inv_type="info"
mkdir -p "$inv_dir"

emit_real() {
  local tok="${1:-}" log="$work/cmux-send.log"
  : > "$log"
  MOCK_LOG="$log" PATH="$mockbin:$PATH" \
    LETTERBOX_DIR="$inv_dir" \
    LETTERBOX_CMUX_PATTERNS="$work/cmux-patterns.tsv" \
    LETTERBOX_CMUX_SUBMIT=1 \
    "$adapter" "$inv_to" "$inv_type" ${tok:+"$tok"} >/dev/null 2>&1 || true
  sed -n 's/^send --surface surface:[0-9][0-9]* //p' "$log" | head -1
}

real_v02="$(emit_real)"
real_v03="$(emit_real a1b2c3d4)"
if [[ -z "$real_v02" || -z "$real_v03" ]]; then
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
  printf '%s' "$s"
}
canon_v02="$(slot "$real_v02")"
canon_v03="$(slot "$real_v03")"

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
  s="${s//<8-lowercase-hex>/<TOKEN>}"
  s="${s//<8hex>/<TOKEN>}"
  if [[ "$s" =~ \ ·\ [0-9a-f]{8}$ ]]; then
    s="${s% · *} · <TOKEN>"
  fi
  s="${s//<type>/<TYPE>}"
  s="${s//<agent>/<AGENT>}"
  s="${s//<letterbox>/<DIR>}"
  s="${s//<LETTERBOX_DIR>/<DIR>}"
  printf '%s\n' "$s"
}

shape_ok() {
  local n="$1"
  [[ "$n" == "$canon_v02" || "$n" == "$canon_v03" ]] && return 0
  # Prefix fragments (skill "MUST start with …") are allowed if they are a
  # real prefix of the adapter shape — not a different sentence.
  [[ -n "$n" && "$canon_v02" == "$n"* ]] && return 0
  [[ -n "$n" && "$canon_v03" == "$n"* ]] && return 0
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
      fails=$((fails + 1))
    fi
  done < "$f"
}

scan_file README.md
scan_file SPEC.md
shopt -s nullglob
for f in skills/*/SKILL.md skills/SKILL.md; do
  scan_file "$f"
done
shopt -u nullglob

if (( fails > 0 )); then
  echo "doorbell-docs-drift: FAIL ($fails)" >&2
  exit 1
fi
echo "doorbell-docs-drift: PASS"
exit 0
