#!/usr/bin/env bash
# Public-safe v0.2 lifecycle matrix (P0/P1/P2). Neutral identities only.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
letterbox="$root/bin/letterbox"
PASS=0
FAIL=0
BLOCK_FAILED=0

# fail marks the current block; pass must not green-wash a failed block.
fail() {
  echo "FAIL: $*" >&2
  FAIL=$((FAIL + 1))
  BLOCK_FAILED=1
  return 0
}
pass() {
  if [[ "$BLOCK_FAILED" == 1 ]]; then
    echo "BLOCK FAILED: $*" >&2
    BLOCK_FAILED=0
    return 0
  fi
  echo "PASS: $*"
  PASS=$((PASS + 1))
}
# Reset at block entry so an unreported failure cannot leak into the next block.
begin_block() { BLOCK_FAILED=0; }

# Portable checksum (macOS shasum; Debian may only have sha256sum)
file_sha() {
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print $1}'
  elif command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    # openssl is common on bare images
    openssl dgst -sha256 "$1" | awk '{print $NF}'
  fi
}

box=""
cleanup() {
  if [[ -n "${box:-}" && -d "$box" ]]; then
    rm -rf "$box"
  fi
  return 0
}
trap cleanup EXIT

new_box() {
  cleanup
  box="$(mktemp -d "${TMPDIR:-/tmp}/lb-v02.XXXXXX")"
  LETTERBOX_DIR="$box" "$letterbox" init planner reviewer >/dev/null
}

lb() {
  local agent="$1"; shift
  LETTERBOX_DIR="$box" LETTERBOX_AGENT="$agent" "$letterbox" "$@"
}

send_task() {
  printf '%s\n' 'task body' | lb planner send reviewer delegate task-item --ack >/dev/null
  task="$(find "$box/reviewer/inbox" -name '*.md' -type f -print -quit)"
  task_id="$(basename "$task" .md)"
}

send_info() {
  printf '%s\n' 'info body' | lb planner send reviewer info note-item >/dev/null
  info="$(find "$box/reviewer/inbox" -name '*.md' -type f -print -quit)"
  info_id="$(basename "$info" .md)"
}

echo "=== P0 semantics core ==="

# B1
begin_block
new_box; send_task
orig_hash="$(file_sha "$task")"
printf 'accepted\n' | lb reviewer reply "$task_id" ack reply-slug >/dev/null
ack_file="$(find "$box/planner/inbox" -name '*--reviewer--ack.md' -type f -print -quit)"
[[ -f "$ack_file" ]] || fail B1-ack-file
[[ -f "$task.ack" ]] || fail B1-stamp
[[ -f "$task" ]] || fail B1-letter-stays
[[ "$(file_sha "$task")" == "$orig_hash" ]] || fail B1-mutated
grep -Fq "re: $task_id" "$ack_file" || fail B1-re
pass B1-ack-stamp-wip

# B2 terminal result + direct
begin_block
printf 'finished\n' | lb reviewer reply "$task_id" result reply-slug >/dev/null
[[ -f "$box/reviewer/processed/$(basename "$task")" ]] || fail B2-archived
[[ ! -e "$task.ack" ]] || fail B2-sidecar-gone
[[ -n "$(find "$box/planner/inbox" -name '*--reviewer--result.md' -print -quit)" ]] || fail B2-result
new_box; send_task
printf 'direct-finish\n' | lb reviewer reply "$task_id" result reply-slug >/dev/null
[[ -f "$box/reviewer/processed/$(basename "$task")" ]] || fail B2-direct
pass B2-result-terminal

# B3 file non-task
begin_block
new_box; send_info
lb reviewer file "$info_id" >/dev/null
[[ -f "$box/reviewer/processed/$(basename "$info")" ]] || fail B3-filed
[[ "$(find "$box/planner/inbox" -name '*.md' 2>/dev/null | wc -l | tr -d ' ')" == 0 ]] || fail B3-no-publish
pass B3-file-nontask

# B4 nack
begin_block
new_box; send_task
printf 'declined\n' | lb reviewer reply "$task_id" nack reply-slug >/dev/null
[[ -f "$box/reviewer/processed/$(basename "$task")" ]] || fail B4-archived
[[ -n "$(find "$box/planner/inbox" -name '*--reviewer--nack.md' -print -quit)" ]] || fail B4-nack
pass B4-nack-terminal

# C1 C2 file refuses task
begin_block
new_box; send_task
if lb reviewer file "$task_id" 2>/dev/null; then fail C1-unacked; fi
printf 'accepted\n' | lb reviewer reply "$task_id" ack reply-slug >/dev/null
if lb reviewer file "$task_id" 2>/dev/null; then fail C2-stamped; fi
pass C1-C2-file-refuses-task

# C3 freeform ownership send
begin_block
new_box
if printf 'x\n' | lb planner send reviewer ack freeform 2>/dev/null; then fail C3-ack; fi
if printf 'x\n' | lb planner send reviewer nack freeform 2>/dev/null; then fail C3-nack; fi
if printf 'x\n' | lb planner send reviewer result freeform 2>/dev/null; then fail C3-result; fi
pass C3-send-refuses-ownership

# C4 delegate without --ack
begin_block
if printf 'x\n' | lb planner send reviewer delegate bare 2>/dev/null; then fail C4; fi
pass C4-delegate-requires-ack

# C5 reply non-task
begin_block
new_box; send_info
if printf 'x\n' | lb reviewer reply "$info_id" ack reply-slug 2>/dev/null; then fail C5; fi
pass C5-reply-refuses-nontask

# C6 done stamped
begin_block
new_box; send_task
printf 'accepted\n' | lb reviewer reply "$task_id" ack reply-slug >/dev/null
ack_file="$(find "$box/planner/inbox" -name '*--reviewer--ack.md' -print -quit)"
if lb reviewer done "$task_id" --reply "$ack_file" 2>/dev/null; then fail C6; fi
pass C6-done-refuses-stamped

# C7 traversal
begin_block
new_box; send_task
planner_info="$(printf 'hi\n' | lb reviewer send planner info hello | sed -n 's/^sent: //p')"
if printf 'x\n' | lb reviewer reply "../../planner/inbox/$(basename "$planner_info")" ack reply-slug 2>/dev/null; then fail C7-accepted; fi
[[ -f "$planner_info" ]] || fail C7-planner-gone
[[ "$(find "$box/planner/inbox" -name '*--reviewer--ack.md' 2>/dev/null | wc -l | tr -d ' ')" == 0 ]] || fail C7-cross-write
pass C7-traversal-refused

# D1 D2 D3 idempotent
begin_block
new_box; send_task
printf 'accepted\n' | lb reviewer reply "$task_id" ack reply-slug >/dev/null
printf 'accepted\n' | lb reviewer reply "$task_id" ack reply-slug >/dev/null
[[ "$(find "$box/planner/inbox" -name '*--reviewer--ack.md' | wc -l | tr -d ' ')" == 1 ]] || fail D1-dup
[[ -f "$task.ack" ]] || fail D1-stamp
printf 'done\n' | lb reviewer reply "$task_id" result reply-slug >/dev/null
printf 'done\n' | lb reviewer reply "$task_id" result reply-slug >/dev/null
[[ "$(find "$box/planner/inbox" -name '*--reviewer--result.md' | wc -l | tr -d ' ')" == 1 ]] || fail D2-dup
new_box; send_info
lb reviewer file "$info_id" >/dev/null
lb reviewer file "$info_id" >/dev/null
[[ "$(find "$box/reviewer/processed" -name '*.md' | wc -l | tr -d ' ')" == 1 ]] || fail D3
pass D1-D2-D3-idempotent

# D4 collision
begin_block
new_box; send_task
printf 'accepted\n' | lb reviewer reply "$task_id" ack reply-slug >/dev/null
if printf 'changed\n' | lb reviewer reply "$task_id" ack reply-slug 2>/dev/null; then fail D4; fi
pass D4-collision-dies

# G1 G2 G3 check
begin_block
new_box; send_task
out="$(lb reviewer check reviewer)"
printf '%s\n' "$out" | grep -Fq '[UNACKED]' || fail G2-unacked
printf '%s\n' "$out" | grep -Eq 'inbox: 1 message' || fail G1-count
printf 'accepted\n' | lb reviewer reply "$task_id" ack reply-slug >/dev/null
out="$(lb reviewer check reviewer)"
printf '%s\n' "$out" | grep -Fq '[ACCEPTED]' || fail G2-accepted
printf 'orphan\n' > "$box/reviewer/inbox/ghost.md.ack"
err="$( { lb reviewer check reviewer >/dev/null; } 2>&1 || true)"
printf '%s\n' "$err" | grep -Fq 'orphan ACK sidecar' || fail G3-warn
[[ -f "$task" ]] || fail G3-tree
pass G1-G2-G3-check

echo "=== P1 crash/race/doorbell ==="

# E1 ln shim
begin_block
new_box; send_task
shim_dir="$box/shim"
mkdir -p "$shim_dir"
cat > "$shim_dir/ln" <<'SH'
#!/usr/bin/env bash
real_ln=/bin/ln
[[ -x /bin/ln ]] || real_ln="$(command -v ln)"
state_file="${LETTERBOX_LN_STATE:?}"
if [[ ! -f "$state_file" ]]; then
  "$real_ln" "$@" || exit $?
  : > "$state_file"
  exit 1
fi
exec "$real_ln" "$@"
SH
chmod +x "$shim_dir/ln"
export LETTERBOX_LN_STATE="$box/ln-state"
set +e
PATH="$shim_dir:$PATH" printf 'accepted\n' | LETTERBOX_DIR="$box" LETTERBOX_AGENT=reviewer "$letterbox" reply "$task_id" ack reply-slug >/dev/null 2>&1
set -e
PATH="$shim_dir:$PATH" printf 'accepted\n' | LETTERBOX_DIR="$box" LETTERBOX_AGENT=reviewer "$letterbox" reply "$task_id" ack reply-slug >/dev/null
[[ "$(find "$box/planner/inbox" -name '*--reviewer--ack.md' | wc -l | tr -d ' ')" == 1 ]] || fail E1-acks
[[ -f "$task.ack" ]] || fail E1-stamp
pass E1-ln-shim-retry
unset LETTERBOX_LN_STATE

# E2 retry after terminal publish with letter restored
begin_block
new_box; send_task
printf 'done\n' | lb reviewer reply "$task_id" result reply-slug >/dev/null
if [[ -f "$box/reviewer/processed/$(basename "$task")" ]]; then
  mv "$box/reviewer/processed/$(basename "$task")" "$box/reviewer/inbox/"
fi
printf 'stale\n' > "$box/reviewer/inbox/$(basename "$task").ack"
printf 'done\n' | lb reviewer reply "$task_id" result reply-slug >/dev/null
[[ -f "$box/reviewer/processed/$(basename "$task")" ]] || fail E2-archive
[[ ! -e "$box/reviewer/inbox/$(basename "$task").ack" ]] || fail E2-sidecar
[[ "$(find "$box/planner/inbox" -name '*--reviewer--result.md' | wc -l | tr -d ' ')" == 1 ]] || fail E2-dup-result
pass E2-retry-after-publish

# E3 pid-less lock
begin_block
new_box; send_task
mkdir "$task.lifecycle.lock"
sleep 2
printf 'accepted\n' | lb reviewer reply "$task_id" ack reply-slug >/dev/null
[[ -f "$task.ack" ]] || fail E3-stamp
pass E3-pidless-lock-recover

# F1 double ack — both racers must exit 0
begin_block
new_box; send_task
printf 'accepted\n' | lb reviewer reply "$task_id" ack reply-slug >/dev/null &
p1=$!
printf 'accepted\n' | lb reviewer reply "$task_id" ack reply-slug >/dev/null &
p2=$!
ec1=0; wait "$p1" || ec1=$?
ec2=0; wait "$p2" || ec2=$?
[[ "$ec1" -eq 0 ]] || fail "F1-racer1-exit-$ec1"
[[ "$ec2" -eq 0 ]] || fail "F1-racer2-exit-$ec2"
[[ "$(find "$box/planner/inbox" -name '*--reviewer--ack.md' | wc -l | tr -d ' ')" == 1 ]] || fail F1-acks
[[ -f "$task.ack" ]] || fail F1-stamp
pass F1-double-ack-race

# F2 ack vs result
begin_block
new_box; send_task
printf 'accepted\n' | lb reviewer reply "$task_id" ack reply-slug >/dev/null &
a=$!
printf 'finished\n' | lb reviewer reply "$task_id" result reply-slug >/dev/null &
r=$!
wait "$a" || true
wait "$r" || true
[[ -f "$box/reviewer/processed/$(basename "$task")" ]] || fail F2-not-terminal
[[ ! -e "$box/reviewer/inbox/$(basename "$task").ack" ]] || fail F2-orphan-sidecar
acks=$(find "$box/planner/inbox" -name '*--reviewer--ack.md' | wc -l | tr -d ' ')
results=$(find "$box/planner/inbox" -name '*--reviewer--result.md' | wc -l | tr -d ' ')
[[ "$acks" -le 1 ]] || fail F2-acks
[[ "$results" == 1 ]] || fail F2-results
pass F2-ack-result-race

# H1 H2 H3 doorbell
begin_block
new_box; send_task
bell_log="$box/bell.log"
cat > "$box/bell.sh" <<'SH'
#!/usr/bin/env bash
log="${LETTERBOX_BELL_LOG:?}"
letter="${LETTERBOX_BELL_LETTER:?}"
{
  printf 'bell %s %s %s\n' "$1" "$2" "$3"
  if [[ -f "$letter.ack" ]]; then echo stamp=present; else echo stamp=absent; fi
  if [[ -f "$letter" ]]; then echo letter=inbox
  elif [[ -f "$(dirname "$letter")/../processed/$(basename "$letter")" ]]; then echo letter=processed
  else echo letter=missing; fi
} >> "$log"
SH
chmod +x "$box/bell.sh"
export LETTERBOX_DOORBELL="$box/bell.sh"
export LETTERBOX_BELL_LOG="$bell_log"
export LETTERBOX_BELL_LETTER="$task"
: > "$bell_log"
printf 'accepted\n' | LETTERBOX_DIR="$box" LETTERBOX_AGENT=reviewer LETTERBOX_DOORBELL="$box/bell.sh" \
  LETTERBOX_BELL_LOG="$bell_log" LETTERBOX_BELL_LETTER="$task" \
  "$letterbox" reply "$task_id" ack reply-slug --now >/dev/null
grep -Fq 'stamp=present' "$bell_log" || fail H1-order
: > "$bell_log"
printf 'accepted\n' | LETTERBOX_DIR="$box" LETTERBOX_AGENT=reviewer LETTERBOX_DOORBELL="$box/bell.sh" \
  LETTERBOX_BELL_LOG="$bell_log" LETTERBOX_BELL_LETTER="$task" \
  "$letterbox" reply "$task_id" ack reply-slug --now >/dev/null
[[ ! -s "$bell_log" ]] || fail H2-rerun-bell
: > "$bell_log"
if printf 'other\n' | LETTERBOX_DIR="$box" LETTERBOX_AGENT=reviewer LETTERBOX_DOORBELL="$box/bell.sh" \
  LETTERBOX_BELL_LOG="$bell_log" LETTERBOX_BELL_LETTER="$task" \
  "$letterbox" reply "$task_id" ack reply-slug --now 2>/dev/null; then fail H3-should-fail; fi
[[ ! -s "$bell_log" ]] || fail H3-bell-on-fail
pass H1-H2-H3-doorbell
unset LETTERBOX_DOORBELL LETTERBOX_BELL_LOG LETTERBOX_BELL_LETTER

echo "=== P2 hardening ==="

# I1 CRLF
begin_block
new_box
{
  printf '%s\r\n' '---' 'id: crlf-task-1' 'from: planner' 'to: reviewer' 'type: delegate' 're: ' 'priority: next' 'requires_ack: true' 'deadline: ' '---' 'crlf body'
} > "$box/reviewer/inbox/crlf-task-1.md"
printf 'ok\n' | lb reviewer reply crlf-task-1 ack reply-slug >/dev/null
[[ -f "$box/reviewer/inbox/crlf-task-1.md.ack" ]] || fail I1-ack
{
  printf '%s\r\n' '---' 'id: crlf-info-1' 'from: planner' 'to: reviewer' 'type: info' 're: ' 'priority: next' 'requires_ack: false' 'deadline: ' '---' 'info'
} > "$box/reviewer/inbox/crlf-info-1.md"
lb reviewer file crlf-info-1 >/dev/null
[[ -f "$box/reviewer/processed/crlf-info-1.md" ]] || fail I1-file
pass I1-crlf

# A1 thread
begin_block
new_box
printf 'work\n' | lb planner send reviewer delegate threaded --ack --thread epic-42 >/dev/null
task="$(find "$box/reviewer/inbox" -name '*.md' -print -quit)"
task_id="$(basename "$task" .md)"
grep -Fq 'thread: epic-42' "$task" || fail A1-send-thread
printf 'accepted\n' | lb reviewer reply "$task_id" ack reply-slug >/dev/null
ack_file="$(find "$box/planner/inbox" -name '*--reviewer--ack.md' -print -quit)"
grep -Fq 'thread: epic-42' "$ack_file" || fail A1-reply-thread
new_box; send_task
printf 'accepted\n' | lb reviewer reply "$task_id" ack reply-slug >/dev/null
ack_file="$(find "$box/planner/inbox" -name '*--reviewer--ack.md' -print -quit)"
grep -Fq "thread: $task_id" "$ack_file" || fail A1-default-thread
if printf 'x\n' | lb planner send reviewer delegate badthread --ack --thread 'bad thread!' 2>/dev/null; then fail A1-bad; fi
pass A1-thread

echo
echo "lifecycle v0.2: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
