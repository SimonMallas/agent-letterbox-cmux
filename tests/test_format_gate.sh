#!/usr/bin/env bash
# Format gate G: absent and exact flat-v1 stay, everything else refuses first.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
letterbox="$root/bin/letterbox"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
ID='2026-11-13T120001-alpha-info-live-a0000001'
BODY='synthetic-body-marker'
ACTION='this release reads flat-v1 only, use a release that supports the box format'

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

seed() {
  local box="$1"
  mkdir -p "$box/alpha/inbox" "$box/beta/inbox" "$box/alpha/processed" "$box/beta/processed"
  cat > "$box/alpha/inbox/${ID}.md" <<EOF
---
id: ${ID}
from: alpha
to: beta
type: info
re:
thread: ${ID}
priority: next
requires_ack: false
deadline:
---
${BODY}
EOF
}

lb() {
  local box="$1"; shift
  LETTERBOX_DIR="$box" LETTERBOX_AGENT=alpha LETTERBOX_DOORBELL=/nonexistent-test-adapter \
    "$letterbox" "$@"
}

expect_refuse() {
  local box="$1" shown="$2"; shift 2
  local out err code=0
  local expect="letterbox: format refusal: box format is ${shown}; ${ACTION}"
  out="$(mktemp)"; err="$(mktemp)"
  lb "$box" "$@" >"$out" 2>"$err" || code=$?
  [[ "$code" -ne 0 ]] || fail "exit 0 for: $*"
  printf '%s\n' "$expect" | cmp -s - "$err" || fail "stderr for: $* ($(cat "$err"))"
  [[ ! -s "$out" ]] || fail "stdout for: $*"
  ! grep -q "$BODY" "$out" "$err" || fail "body leaked for: $*"
  rm -f "$out" "$err"
}

shown_for() {
  case "$1" in
    month) printf '%s' "'month-v2'" ;;
    unknown) printf '%s' "'nope'" ;;
    padded) printf '%s' "'flat-v1 '" ;;
    *) printf '%s' unreadable ;;
  esac
}

capture() {
  local box="$1"; shift
  local out err code=0
  out="$(mktemp)"; err="$(mktemp)"
  lb "$box" "$@" >"$out" 2>"$err" || code=$?
  printf '%s\n' "$code"
  cat "$out"
  printf '\n--err--\n'
  cat "$err"
  rm -f "$out" "$err"
}

fresh() {
  local mark="$1" box
  box="$(mktemp -d "$work/box.XXXXXX")"
  seed "$box"
  case "$mark" in
    absent) ;;
    flat) printf 'flat-v1\n' > "$box/format.mark" ;;
    flat-bare) printf 'flat-v1' > "$box/format.mark" ;;
    month) printf 'month-v2\n' > "$box/format.mark" ;;
    unknown) printf 'nope\n' > "$box/format.mark" ;;
    empty) : > "$box/format.mark" ;;
    padded) printf 'flat-v1 \n' > "$box/format.mark" ;;
    twonl) printf 'flat-v1\n\n' > "$box/format.mark" ;;
    symlink)
      printf 'flat-v1\n' > "$box/format.mark.real"
      ln -s format.mark.real "$box/format.mark"
      ;;
    dir) mkdir "$box/format.mark" ;;
    oversized) dd if=/dev/zero bs=65 count=1 of="$box/format.mark" >/dev/null 2>&1 ;;
    nonascii) printf 'month-\377\n' > "$box/format.mark" ;;
  esac
  printf '%s\n' "$box"
}

printf '%s\n' '=== absent and exact flat-v1 match ==='
absent="$(fresh absent)"
flat="$(fresh flat)"
bare="$(fresh flat-bare)"
for args in "check" "check --thread $ID" "check --maps" "read $ID" "query" "query --compat-v2" "nudge $ID"; do
  # shellcheck disable=SC2086
  a="$(capture "$absent" $args)"
  # shellcheck disable=SC2086
  b="$(capture "$flat" $args)"
  # shellcheck disable=SC2086
  c="$(capture "$bare" $args)"
  [[ "$a" == "$b" ]] || fail "flat-v1 differs from absent for: $args"
  [[ "$a" == "$c" ]] || fail "bare flat-v1 differs from absent for: $args"
done
grep -q "$BODY" <<<"$(lb "$flat" read "$ID")" || fail 'flat-v1 read lost the body'

printf '%s\n' '=== bad marks refuse before the letter ==='
for mark in month unknown empty padded twonl symlink dir oversized nonascii; do
  box="$(fresh "$mark")"
  before="$(find "$box" -print | sort)"
  shown="$(shown_for "$mark")"
  expect_refuse "$box" "$shown" check
  expect_refuse "$box" "$shown" check --thread "$ID"
  expect_refuse "$box" "$shown" check --maps
  expect_refuse "$box" "$shown" read "$ID"
  expect_refuse "$box" "$shown" query
  expect_refuse "$box" "$shown" query --compat-v2
  expect_refuse "$box" "$shown" nudge "$ID"
  expect_refuse "$box" "$shown" ring alpha info "$ID"
  expect_refuse "$box" "$shown" lint-notes
  expect_refuse "$box" "$shown" file "$ID"
  expect_refuse "$box" "$shown" send beta info hello <<<"$BODY"
  expect_refuse "$box" "$shown" reply "$ID" result ok <<<"$BODY"
  after="$(find "$box" -print | sort)"
  [[ "$before" == "$after" ]] || fail "state changed for mark $mark"
  grep -q "$BODY" "$box/alpha/inbox/${ID}.md" || fail "letter damaged for mark $mark"
done

printf '%s\n' '=== symlinked seat and symlinked box ==='
foreign="$(fresh month)"
legacy="$(mktemp -d "$work/legacy.XXXXXX")"
mkdir -p "$legacy/beta/inbox" "$legacy/beta/processed"
ln -s "$foreign/alpha" "$legacy/alpha"
expect_refuse "$legacy" "'month-v2'" check
linkbox="$(mktemp -d "$work/link.XXXXXX")"
ln -s "$foreign" "$linkbox/box"
expect_refuse "$linkbox/box" "'month-v2'" read "$ID"

printf '%s\n' '=== path resolves to the owning box ==='
plain="$(fresh absent)"
rm -rf "$plain/alpha/inbox"
ln -s "$foreign/alpha/inbox" "$plain/alpha/inbox"
target="$foreign/alpha/inbox/${ID}.md"
expect_refuse "$plain" "'month-v2'" file "$target"
[[ -f "$target" ]] || fail 'path-form file removed the foreign letter'
expect_refuse "$plain" "'month-v2'" reply "$target" result ok <<<"$BODY"
[[ -f "$target" ]] || fail 'path-form reply removed the foreign letter'

printf '%s\n' '=== version does not read the box ==='
ver="$(LETTERBOX_DIR="$foreign" "$letterbox" --version)"
grep -q '^letterbox ' <<<"$ver" || fail 'version refused a marked box'

printf '%s\n' '=== fast path refusal does not fall back ==='
fallback="$(fresh absent)"
real_python="$(command -v python3)"
wrap="$(mktemp -d "$work/py.XXXXXX")"
cat > "$wrap/python3" <<EOF
#!/usr/bin/env bash
if [[ "\$*" == *fastpath.py* ]]; then
  printf '%s\n' "letterbox: format refusal: box format is 'month-v2'; ${ACTION}" >&2
  exit 1
fi
exec "$real_python" "\$@"
EOF
chmod +x "$wrap/python3"
for args in "check" "read $ID"; do
  out="$(mktemp)"; err="$(mktemp)"; code=0
  # shellcheck disable=SC2086
  PATH="$wrap:$PATH" lb "$fallback" $args >"$out" 2>"$err" || code=$?
  [[ "$code" -eq 1 ]] || fail "fast fallback exit $code for: $args"
  printf '%s\n' "letterbox: format refusal: box format is 'month-v2'; ${ACTION}" | cmp -s - "$err" \
    || fail "fast fallback stderr for: $args ($(cat "$err"))"
  [[ ! -s "$out" ]] || fail "fast fallback stdout for: $args ($(cat "$out"))"
  ! grep -q "$BODY" "$out" || fail "fast fallback printed the body for: $args"
  ! grep -q 'inbox:' "$out" || fail "fast fallback printed the inbox for: $args"
  rm -f "$out" "$err"
done
grep -q "$BODY" "$fallback/alpha/inbox/${ID}.md" || fail 'fast fallback damaged the letter'

printf '%s\n' '=== leaf symlink ==='
base_root="$(mktemp -d "$work/base.XXXXXX")"
mkdir -p "$base_root/bin"
# Frozen pre-gate tree. Once this candidate is committed, HEAD is the candidate,
# so an archive of HEAD would compare the candidate with itself.
cp "$root/tests/fixtures/letterbox-before-ring-retry" "$base_root/bin/letterbox"
chmod +x "$base_root/bin/letterbox"
cp -R "$root/tests/fixtures/pre-gate/lib" "$base_root/"
cp "$root/tests/fixtures/pre-gate/VERSION" "$base_root/VERSION"
base_lb="$base_root/bin/letterbox"
[[ -x "$base_lb" ]] || fail 'baseline letterbox missing'
[[ -f "$base_root/lib/query/strict.py" ]] || fail 'baseline strict.py missing'
if cmp -s "$base_lb" "$letterbox"; then
  fail 'baseline letterbox is the candidate'
fi
if cmp -s "$base_root/lib/query/strict.py" "$root/lib/query/strict.py"; then
  fail 'baseline strict.py is the candidate'
fi

# Source box, unmarked. The only inbox letter is a symlink to $1.
leaf_src() {
  local target="$1" src
  src="$(mktemp -d "$work/src.XXXXXX")"
  mkdir -p "$src/alpha/inbox" "$src/alpha/processed" "$src/beta/inbox" "$src/beta/processed"
  ln -s "$target" "$src/alpha/inbox/${ID}.md"
  printf '%s\n' "$src"
}

cmp_ro() {
  local box="$1"; shift
  local outa erra outb errb ca=0 cb=0
  outa="$(mktemp)"; erra="$(mktemp)"; outb="$(mktemp)"; errb="$(mktemp)"
  LETTERBOX_DIR="$box" LETTERBOX_AGENT=alpha LETTERBOX_DOORBELL=/nonexistent-test-adapter \
    "$letterbox" "$@" >"$outa" 2>"$erra" || ca=$?
  LETTERBOX_DIR="$box" LETTERBOX_AGENT=alpha LETTERBOX_DOORBELL=/nonexistent-test-adapter \
    "$base_lb" "$@" >"$outb" 2>"$errb" || cb=$?
  [[ "$ca" == "$cb" ]] || fail "leaf parity exit $ca vs $cb for: $*"
  cmp -s "$outa" "$outb" || fail "leaf parity stdout for: $*"
  cmp -s "$erra" "$errb" || fail "leaf parity stderr for: $*"
  rm -f "$outa" "$erra" "$outb" "$errb"
}

foreign="$(fresh month)"
target="$foreign/alpha/inbox/${ID}.md"
src="$(leaf_src "$target")"
expect_refuse "$src" "'month-v2'" read "$ID"
expect_refuse "$src" "'month-v2'" check
expect_refuse "$src" "'month-v2'" check --thread "$ID"
expect_refuse "$src" "'month-v2'" file "$ID"
expect_refuse "$src" "'month-v2'" reply "$ID" result ok <<<"$BODY"
expect_refuse "$src" "'month-v2'" nudge "$ID"
expect_refuse "$src" "'month-v2'" progress "$ID" 'note'
expect_refuse "$src" "'month-v2'" token a0000001
printf 'reply-body\n' > "$src/beta/inbox/reply.md"
expect_refuse "$src" "'month-v2'" done "$ID" --reply "$src/beta/inbox/reply.md"
[[ -f "$target" && -L "$src/alpha/inbox/${ID}.md" ]] || fail 'marked leaf moved a letter'
grep -q "$BODY" "$target" || fail 'marked leaf rewrote the foreign letter'

# A marked symlink shares the inbox. Its header cannot be skipped, so the
# command refuses before the regular neighbour is served.
neighbour="$(leaf_src "$target")"
other='2026-11-13T120002-alpha-info-live-a0000002'
cat > "$neighbour/alpha/inbox/${other}.md" <<EOF
---
id: ${other}
from: alpha
to: beta
type: info
thread: ${other}
priority: next
requires_ack: false
---
neighbour-body
EOF
expect_refuse "$neighbour" "'month-v2'" read "$other"
expect_refuse "$neighbour" "'month-v2'" check
[[ -f "$neighbour/alpha/inbox/${other}.md" && -L "$neighbour/alpha/inbox/${ID}.md" ]] \
  || fail 'marked neighbour moved a letter'

# Unmarked foreign box: same bytes as 9a583f2.
plain_foreign="$(fresh absent)"
plain_src="$(leaf_src "$plain_foreign/alpha/inbox/${ID}.md")"
cmp_ro "$plain_src" read "$ID"
cmp_ro "$plain_src" check
cmp_ro "$plain_src" token a0000001
grep -q "$BODY" <<<"$(lb "$plain_src" read "$ID")" || fail 'unmarked leaf hid the body'

# Dangling, chain, and a file outside any box.
dangling="$(leaf_src "$plain_foreign/alpha/inbox/missing.md")"
cmp_ro "$dangling" read "$ID"
cmp_ro "$dangling" check
chain_dir="$(mktemp -d "$work/chain.XXXXXX")"
ln -s "$plain_foreign/alpha/inbox/${ID}.md" "$chain_dir/mid"
chain_src="$(leaf_src "$chain_dir/mid")"
cmp_ro "$chain_src" read "$ID"
marked_chain="$(leaf_src "$chain_dir/mid2")"
ln -s "$target" "$chain_dir/mid2"
expect_refuse "$marked_chain" "'month-v2'" read "$ID"
outside="$(mktemp -d "$work/outside.XXXXXX")"
cp "$plain_foreign/alpha/inbox/${ID}.md" "$outside/note.md"
outside_src="$(leaf_src "$outside/note.md")"
cmp_ro "$outside_src" read "$ID"
cmp_ro "$outside_src" check

printf '%s\n' '=== direct path into a marked box ==='
# Real directories, so preflight does not see the other box. The path
# gate has to refuse alone: c8035ea6 added "message not found".
direct="$(fresh absent)"
marked="$(fresh month)"
direct_target="$marked/alpha/inbox/${ID}.md"
printf 'x\n' > "$direct/alpha/inbox/reply.md"
expect_refuse "$direct" "'month-v2'" file "$direct_target"
expect_refuse "$direct" "'month-v2'" reply "$direct_target" result ok <<<"$BODY"
expect_refuse "$direct" "'month-v2'" reply "$direct_target" ack ok <<<"$BODY"
expect_refuse "$direct" "'month-v2'" reply "$direct_target" nack no <<<"$BODY"
expect_refuse "$direct" "'month-v2'" done "$direct_target" --reply "$direct/alpha/inbox/reply.md"
expect_refuse "$direct" "'month-v2'" done "$ID" --reply "$direct_target"
via="$work/via-marked"
ln -s "$direct_target" "$via"
expect_refuse "$direct" "'month-v2'" file "$via"
expect_refuse "$direct" "'month-v2'" reply "$via" result ok <<<"$BODY"
[[ -f "$direct_target" && -f "$direct/alpha/inbox/${ID}.md" && -L "$via" ]] \
  || fail 'direct path moved a letter'
grep -q "$BODY" "$direct_target" || fail 'direct path rewrote the foreign letter'
# read, nudge, and progress reject a path before the gate. Same bytes as 9a583f2.
cmp_ro "$direct" read "$direct_target"
cmp_ro "$direct" nudge "$direct_target"
cmp_ro "$direct" progress "$direct_target" note
grep -q "$BODY" "$direct_target" || fail 'path reject read the foreign letter'
# No mark on the other box: the own-inbox refusal, byte for byte with 9a583f2.
plain_path="$(fresh absent)"
plain_target="$plain_path/alpha/inbox/${ID}.md"
cmp_ro "$direct" file "$plain_target"
cmp_ro "$direct" reply "$plain_target" result ok <<<"$BODY"
cmp_ro "$direct" done "$plain_target" --reply "$direct/alpha/inbox/reply.md"
[[ -f "$plain_target" && -f "$direct/alpha/inbox/${ID}.md" ]] || fail 'unmarked path moved a letter'

printf '%s\n' '=== alias duplicate ==='
sep=$'\xc2\xb7'
disp_id="$(printf '%s %s %s' '2026-11-13T120001' "$sep" 'a0000001')"
other_id='2026-11-13T120002-beta-info-live-b0000002'
disp_other="$(printf '%s %s %s' '2026-11-13T120002' "$sep" 'b0000002')"
other_body='foreign-body-marker'

write_other() {
  local dest="$1" ident="$2" body="$3" sender="${4:-beta}"
  mkdir -p "$(dirname "$dest")"
  cat > "$dest" <<EOF
---
id: ${ident}
from: ${sender}
to: alpha
type: info
re:
thread: ${ident}
priority: next
requires_ack: false
deadline:
---
${body}
EOF
}

# Copies, because file, reply, and done move letters. Listings stay relative.
cmp_copy() {
  local box="$1" input="$2"; shift 2
  local a b arg ca=0 cb=0 lista listb
  local -a args_a=() args_b=()
  a="$(mktemp -d "$work/copa.XXXXXX")"
  b="$(mktemp -d "$work/copb.XXXXXX")"
  cp -R "$box/." "$a/"
  cp -R "$box/." "$b/"
  for arg in "$@"; do
    case "$arg" in
      @copy/*)
        args_a+=("$a/${arg#@copy/}")
        args_b+=("$b/${arg#@copy/}")
        ;;
      *)
        args_a+=("$arg")
        args_b+=("$arg")
        ;;
    esac
  done
  local outa erra outb errb
  outa="$(mktemp)"; erra="$(mktemp)"; outb="$(mktemp)"; errb="$(mktemp)"
  LETTERBOX_DIR="$a" LETTERBOX_AGENT=alpha LETTERBOX_DOORBELL=/nonexistent-test-adapter \
    "$letterbox" "${args_a[@]}" >"$outa" 2>"$erra" <<<"$input" || ca=$?
  LETTERBOX_DIR="$b" LETTERBOX_AGENT=alpha LETTERBOX_DOORBELL=/nonexistent-test-adapter \
    "$base_lb" "${args_b[@]}" >"$outb" 2>"$errb" <<<"$input" || cb=$?
  [[ "$ca" == "$cb" ]] || fail "alias parity exit $ca vs $cb for: ${args_a[*]}"
  cmp -s "$outa" "$outb" || fail "alias parity stdout for: ${args_a[*]}"
  cmp -s "$erra" "$errb" || fail "alias parity stderr for: ${args_a[*]}"
  lista="$(cd "$a" && find . -print | sort)"
  listb="$(cd "$b" && find . -print | sort)"
  [[ "$lista" == "$listb" ]] || fail "alias parity tree for: ${args_a[*]}"
  rm -f "$outa" "$erra" "$outb" "$errb"
  rm -rf "$a" "$b"
}

# Regular canonical letter plus a differently named symlink, same header id.
dup_foreign="$(fresh absent)"
dup="$(mktemp -d "$work/dup.XXXXXX")"
mkdir -p "$dup/alpha/inbox" "$dup/alpha/processed" "$dup/beta/inbox" "$dup/beta/processed"
cp "$dup_foreign/alpha/inbox/${ID}.md" "$dup/alpha/inbox/${ID}.md"
ln -s "$dup_foreign/alpha/inbox/${ID}.md" "$dup/alpha/inbox/different-name.md"
printf 'x\n' > "$dup/alpha/inbox/reply.md"
cmp_ro "$dup" read "$ID"
cmp_ro "$dup" read "$disp_id"
cmp_ro "$dup" read a0000001
cmp_copy "$dup" '' file "$ID"
cmp_copy "$dup" "$BODY" reply "$ID" result ok
cmp_copy "$dup" '' done "$ID" --reply @copy/alpha/inbox/reply.md
cmp_copy "$dup" '' nudge "$ID"
[[ -f "$dup/alpha/inbox/${ID}.md" && -L "$dup/alpha/inbox/different-name.md" ]] \
  || fail 'duplicate read moved a letter'

# Two symlinks, same header id. No regular file. done names a file, so
# this is not ambiguous on either build: the filename is missing.
two="$(mktemp -d "$work/two.XXXXXX")"
mkdir -p "$two/alpha/inbox" "$two/alpha/processed" "$two/beta/inbox" "$two/beta/processed"
ln -s "$dup_foreign/alpha/inbox/${ID}.md" "$two/alpha/inbox/one.md"
ln -s "$dup_foreign/alpha/inbox/${ID}.md" "$two/alpha/inbox/two.md"
printf 'x\n' > "$two/alpha/inbox/reply.md"
cmp_ro "$two" read "$ID"
cmp_ro "$two" read "$disp_id"
cmp_ro "$two" read a0000001
cmp_copy "$two" '' file "$ID"
cmp_copy "$two" '' nudge "$ID"
cmp_copy "$two" '' done "$ID" --reply @copy/alpha/inbox/reply.md

# Symlink whose header id differs. The matching letter is the unique hit.
alt_foreign="$(mktemp -d "$work/altf.XXXXXX")"
write_other "$alt_foreign/beta/inbox/${other_id}.md" "$other_id" "$other_body" beta
alt="$(mktemp -d "$work/alt.XXXXXX")"
mkdir -p "$alt/alpha/inbox" "$alt/alpha/processed" "$alt/beta/inbox" "$alt/beta/processed"
cp "$dup_foreign/alpha/inbox/${ID}.md" "$alt/alpha/inbox/${ID}.md"
ln -s "$alt_foreign/beta/inbox/${other_id}.md" "$alt/alpha/inbox/alias.md"
cat > "$alt/alpha/inbox/done-reply.md" <<EOF
---
id: 2026-11-13T120003-alpha-result-done-a0000003
from: alpha
to: alpha
type: result
re: ${ID}
thread: ${ID}
priority: next
requires_ack: false
deadline:
---
done-reply
EOF
cmp_ro "$alt" read "$ID"
cmp_ro "$alt" read "$other_id"
cmp_ro "$alt" read "$disp_id"
cmp_ro "$alt" read "$disp_other"
cmp_ro "$alt" read a0000001
cmp_ro "$alt" read b0000002
cmp_copy "$alt" '' file "$ID"
cmp_copy "$alt" '' file "$other_id"
cmp_copy "$alt" '' nudge "$ID"
cmp_copy "$alt" '' nudge "$other_id"
cmp_copy "$alt" "$BODY" reply "$ID" result ok
cmp_copy "$alt" '' done "$ID" --reply @copy/alpha/inbox/done-reply.md
grep -q "$BODY" <<<"$(lb "$alt" read "$ID")" || fail 'unique id hid the regular body'
grep -q "$other_body" <<<"$(lb "$alt" read "$other_id")" || fail 'unique alias hid the foreign body'

# Marked foreign leaf and a duplicate. Refusal wins, including done:
# the symlink is gated before the filename hit. Nothing from that box is served.
mark_foreign="$(fresh month)"
mark_dup="$(mktemp -d "$work/mdup.XXXXXX")"
mkdir -p "$mark_dup/alpha/inbox" "$mark_dup/alpha/processed" "$mark_dup/beta/inbox" "$mark_dup/beta/processed"
cp "$dup_foreign/alpha/inbox/${ID}.md" "$mark_dup/alpha/inbox/${ID}.md"
ln -s "$mark_foreign/alpha/inbox/${ID}.md" "$mark_dup/alpha/inbox/different-name.md"
printf 'x\n' > "$mark_dup/alpha/inbox/reply.md"
expect_refuse "$mark_dup" "'month-v2'" read "$ID"
expect_refuse "$mark_dup" "'month-v2'" read "$disp_id"
expect_refuse "$mark_dup" "'month-v2'" read a0000001
expect_refuse "$mark_dup" "'month-v2'" file "$ID"
expect_refuse "$mark_dup" "'month-v2'" nudge "$ID"
expect_refuse "$mark_dup" "'month-v2'" done "$ID" --reply "$mark_dup/alpha/inbox/reply.md"
expect_refuse "$mark_dup" "'month-v2'" reply "$ID" result ok <<<"$BODY"
[[ -f "$mark_dup/alpha/inbox/${ID}.md" && -L "$mark_dup/alpha/inbox/different-name.md" ]] \
  || fail 'marked duplicate moved a letter'
grep -q "$BODY" "$mark_foreign/alpha/inbox/${ID}.md" || fail 'marked duplicate rewrote the foreign letter'
grep -q "$BODY" "$mark_dup/alpha/inbox/${ID}.md" || fail 'marked duplicate rewrote the regular letter'

printf '%s\n' 'format gate: PASS'
