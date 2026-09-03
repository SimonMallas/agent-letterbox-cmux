#!/usr/bin/env bash
# Mutation: the private-vocabulary gate must catch residue wherever it lands —
# visible file, hidden dotfile, .github workflow, and a newline-split phrase —
# failing with file:line — and must PASS a clean tree. Expected-failure
# sub-run output is [mut]-prefixed.
#
# Isolation contract:
# - Mutation bytes live only under a unique /tmp mktemp dir (never inside the
#   scanned source tree); trap cleanup on exit.
# - Throwaway repo is `git archive HEAD` + overlay of the working-tree
#   scanner/normalizer, then fresh `git init`. NEVER copy source `.git`
#   (a linked worktree's .git is a pointer; git in the copy would mutate
#   the real index).
# - Source `git status --porcelain` must be byte-identical after success
#   and failure paths.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
gate_name="test_no_private_vocabulary.sh"
self_name="$(basename "$0")"

# Force a directory outside the scanned tree. Do not honour TMPDIR — it can
# point inside the worktree and reintroduce self-contamination.
tmp="$(mktemp -d /tmp/vocab-mut.XXXXXX)"
wt=""
fails=0
fail() {
  echo "FAIL: $*" >&2
  fails=$((fails+1))
  printf 'FAIL: %s\n' "$*" >> "$tmp/outer-fails.log"
}
cleanup() {
  local rc=$?
  if [[ -n "${wt:-}" ]]; then
    git -C "$root" worktree remove --force "$wt" >/dev/null 2>&1 || rm -rf "$wt"
  fi
  # False-green: outer FAIL lines (or a recorded fail count) cannot exit 0.
  if [[ "$rc" -eq 0 ]]; then
    if [[ "${fails:-0}" -ne 0 || -s "$tmp/outer-fails.log" ]]; then
      echo "FAIL: false-green — FAIL recorded but rc=0" >&2
      rc=1
    fi
  fi
  rm -rf "$tmp"
  exit "$rc"
}
trap cleanup EXIT

case "$tmp" in
  "$root"|"$root"/*)
    echo "FAIL: mutation temp dir is inside the scanned tree: $tmp" >&2
    exit 1
    ;;
esac

before="$(git -C "$root" status --porcelain)"

mkdir -p "$tmp/repo/tests"
git -C "$root" archive HEAD | tar -x -C "$tmp/repo"
cp "$root/tests/$gate_name" "$tmp/repo/tests/$gate_name"
chmod +x "$tmp/repo/tests/$gate_name"
if [[ -f "$root/tests/vocab_normalized.py" ]]; then
  cp "$root/tests/vocab_normalized.py" "$tmp/repo/tests/vocab_normalized.py"
  chmod +x "$tmp/repo/tests/vocab_normalized.py"
fi
git -C "$tmp/repo" init -q
git -C "$tmp/repo" add -A
git -C "$tmp/repo" -c user.name="mutation-harness" -c user.email="mutation-harness@local" \
  commit -qm "seed" --no-verify

assert_uncontaminated() {
  local p
  for p in docs/visible-residue.md docs/wrap-residue.md \
           .github/workflows/residue-ci.yml .hidden-residuerc; do
    if [[ -e "$root/$p" ]]; then
      echo "FAIL: source tree contaminated with $p" >&2
      return 1
    fi
  done
  return 0
}

GATE_RC=0
run_gate() { # prints gate output with [mut] prefix; sets GATE_RC
  # Capture expected nonzero with if/else. Do not toggle caller-global errexit.
  local out
  out="$(mktemp /tmp/vocab-mut-out.XXXXXX)"
  if ( cd "$tmp/repo" && "./tests/$gate_name" ) >"$out" 2>&1; then
    GATE_RC=0
  else
    GATE_RC=$?
  fi
  sed 's/^/[mut] | /' "$out"
  rm -f "$out"
}

if ! assert_uncontaminated; then
  fails=$((fails+1))
fi

# 0. Clean tree must PASS.
run_gate
if [[ "$GATE_RC" -eq 0 ]]; then
  echo "PASS: clean tree passes the gate"
else
  fail "gate fails on a clean tree"
fi

plant_and_run() { # $1 relative residue path; $2 payload. Sets GATE_RC; 2=did-not-apply.
  local rel="$1" payload="$2"
  mkdir -p "$tmp/repo/$(dirname "$rel")"
  printf '%s' "$payload" > "$tmp/repo/$rel"
  git -C "$tmp/repo" add -f "$rel"
  if [[ ! -f "$tmp/repo/$rel" ]] || ! git -C "$tmp/repo" ls-files --error-unmatch "$rel" >/dev/null 2>&1; then
    fail "mutation did not apply: $rel"
    rm -f "$tmp/repo/$rel"
    git -C "$tmp/repo" rm -q --cached "$rel" 2>/dev/null || true
    GATE_RC=2
    return 0
  fi
  if ! assert_uncontaminated; then
    fails=$((fails+1))
  fi
  run_gate
  git -C "$tmp/repo" rm -q --cached "$rel"
  rm -f "$tmp/repo/$rel"
}

# 1-3. Residue mutations: visible / .github workflow / hidden dotfile.
# Token built from parts so THIS file is not itself a residue hit.
tele_payload="$(printf 'residue tele''gram here\n')"
for rel in "docs/visible-residue.md" ".github/workflows/residue-ci.yml" ".hidden-residuerc"; do
  plant_and_run "$rel" "$tele_payload"
  if [[ "$GATE_RC" -eq 2 ]]; then
    :
  elif [[ "$GATE_RC" -eq 0 ]]; then
    fail "gate passed with residue at $rel"
  else
    echo "PASS: gate failed on residue at $rel"
  fi
done

# 4. Newline-split forbidden phrase must fail with file:line.
wrap_payload="$(printf 'residue shared''\n''brain here\n')"
mkdir -p "$tmp/repo/docs"
printf '%s' "$wrap_payload" > "$tmp/repo/docs/wrap-residue.md"
git -C "$tmp/repo" add -f docs/wrap-residue.md
if ! git -C "$tmp/repo" ls-files --error-unmatch docs/wrap-residue.md >/dev/null 2>&1; then
  fail "mutation did not apply: docs/wrap-residue.md"
else
  if wrap="$(cd "$tmp/repo" && "./tests/$gate_name" 2>&1)"; then
    wrap_rc=0
  else
    wrap_rc=$?
  fi
  echo "[mut] --- wrap residue → gate rc=$wrap_rc ---"
  printf '%s\n' "$wrap" | sed 's/^/[mut] | /'
  if [[ "$wrap_rc" -eq 0 ]]; then
    fail "gate passed with wrapped private phrase"
  elif [[ "$wrap" != *"docs/wrap-residue.md:"* ]]; then
    fail "wrap hit missing file:line"
  else
    echo "PASS: gate failed on wrapped phrase"
  fi
fi
git -C "$tmp/repo" rm -q --cached docs/wrap-residue.md 2>/dev/null || true
rm -f "$tmp/repo/docs/wrap-residue.md"

# 5. Hits must carry file:line (representative visible-residue case).
mkdir -p "$tmp/repo/docs"
printf '%s' "$tele_payload" > "$tmp/repo/docs/visible-residue.md"
git -C "$tmp/repo" add -f docs/visible-residue.md
if ! git -C "$tmp/repo" ls-files --error-unmatch docs/visible-residue.md >/dev/null 2>&1; then
  fail "mutation did not apply: docs/visible-residue.md"
else
  if hit="$(cd "$tmp/repo" && "./tests/$gate_name" 2>&1)"; then
    :
  else
    :
  fi
  if [[ "$hit" == *"docs/visible-residue.md:1:"* ]]; then
    echo "PASS: hit carries file:line"
  else
    printf '%s\n' "$hit" | sed 's/^/[mut] | /'
    fail "hit missing file:line"
  fi
fi
git -C "$tmp/repo" rm -q --cached docs/visible-residue.md 2>/dev/null || true
rm -f "$tmp/repo/docs/visible-residue.md"

# 6. Clean tree again after mutations are removed.
run_gate
if [[ "$GATE_RC" -eq 0 ]]; then
  echo "PASS: clean tree passes the gate after mutations"
else
  fail "gate fails on a clean tree after mutations"
fi

# Normalizer error must fail the gate (never swallowed).
if [[ -f "$tmp/repo/tests/vocab_normalized.py" ]]; then
  cp "$tmp/repo/tests/vocab_normalized.py" "$tmp/vocab_normalized.py.good"
  printf '%s\n' 'import sys' 'sys.exit(1)' > "$tmp/repo/tests/vocab_normalized.py"
  run_gate
  if [[ "$GATE_RC" -eq 0 ]]; then
    fail "gate passed while normalizer exited 1"
  else
    echo "PASS: gate failed on normalizer error"
  fi
  cp "$tmp/vocab_normalized.py.good" "$tmp/repo/tests/vocab_normalized.py"
fi

if ! assert_uncontaminated; then
  fails=$((fails+1))
fi

# 7. Linked-worktree smoke: harness run from a linked worktree must not
#    mutate the source index. Skip when already inside the smoke.
if [[ -z "${VOCAB_MUT_SKIP_WORKTREE_SMOKE:-}" ]]; then
  wt="$(mktemp -d /tmp/vocab-wt.XXXXXX)"
  rmdir "$wt"
  if git -C "$root" worktree add --detach "$wt" HEAD >/dev/null 2>&1; then
    mkdir -p "$wt/tests"
    cp "$root/tests/$gate_name" "$wt/tests/$gate_name"
    cp "$root/tests/$self_name" "$wt/tests/$self_name"
    chmod +x "$wt/tests/$gate_name" "$wt/tests/$self_name"
    if [[ -f "$root/tests/vocab_normalized.py" ]]; then
      cp "$root/tests/vocab_normalized.py" "$wt/tests/vocab_normalized.py"
      chmod +x "$wt/tests/vocab_normalized.py"
    fi
    if VOCAB_MUT_SKIP_WORKTREE_SMOKE=1 "$wt/tests/$self_name" >/dev/null 2>&1; then
      wt_rc=0
    else
      wt_rc=$?
    fi
    git -C "$root" worktree remove --force "$wt" >/dev/null 2>&1 || rm -rf "$wt"
    wt=""
    after_wt="$(git -C "$root" status --porcelain)"
    if [[ "$wt_rc" -ne 0 ]]; then
      fail "linked-worktree smoke: harness rc=$wt_rc"
    elif [[ "$after_wt" != "$before" ]]; then
      fail "linked-worktree smoke mutated source index"
    else
      echo "PASS: linked-worktree smoke (source index unchanged)"
    fi
  else
    fail "linked-worktree smoke: git worktree add failed"
    rm -rf "$wt"
    wt=""
  fi
fi

after="$(git -C "$root" status --porcelain)"
if [[ "$after" == "$before" ]]; then
  echo "PASS: real worktree/index untouched by harness"
else
  fail "worktree/index changed by harness"
  diff <(printf '%s\n' "$before") <(printf '%s\n' "$after") >&2 || true
fi
if printf '%s\n' "$after" | grep -q "residue"; then
  fail "residue path present in real worktree status"
fi

if [[ "$fails" -ne 0 ]]; then
  echo "vocabulary-gate mutation: FAIL ($fails)" >&2
  exit 1
fi
echo "vocabulary-gate mutation: PASS"
exit 0
