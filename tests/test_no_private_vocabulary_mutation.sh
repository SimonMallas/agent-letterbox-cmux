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
cleanup() {
  local rc=$?
  if [[ -n "${wt:-}" ]]; then
    git -C "$root" worktree remove --force "$wt" >/dev/null 2>&1 || rm -rf "$wt"
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
  local out
  out="$(mktemp /tmp/vocab-mut-out.XXXXXX)"
  set +e
  ( cd "$tmp/repo" && "./tests/$gate_name" ) >"$out" 2>&1
  GATE_RC=$?
  set -e
  sed 's/^/[mut] | /' "$out"
  rm -f "$out"
}

fails=0

if ! assert_uncontaminated; then
  fails=$((fails+1))
fi

# 0. Clean tree must PASS.
run_gate
if [[ "$GATE_RC" -eq 0 ]]; then
  echo "PASS: clean tree passes the gate"
else
  echo "FAIL: gate fails on a clean tree" >&2
  fails=$((fails+1))
fi

plant_and_run() { # $1 relative residue path; $2 payload. Sets GATE_RC; 2=did-not-apply.
  local rel="$1" payload="$2"
  mkdir -p "$tmp/repo/$(dirname "$rel")"
  printf '%s' "$payload" > "$tmp/repo/$rel"
  git -C "$tmp/repo" add -f "$rel"
  if [[ ! -f "$tmp/repo/$rel" ]] || ! git -C "$tmp/repo" ls-files --error-unmatch "$rel" >/dev/null 2>&1; then
    echo "FAIL: mutation did not apply: $rel" >&2
    fails=$((fails+1))
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
    echo "FAIL: gate passed with residue at $rel" >&2
    fails=$((fails+1))
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
  echo "FAIL: mutation did not apply: docs/wrap-residue.md" >&2
  fails=$((fails+1))
else
  wrap="$(cd "$tmp/repo" && "./tests/$gate_name" 2>&1)" && wrap_rc=0 || wrap_rc=$?
  echo "[mut] --- wrap residue → gate rc=$wrap_rc ---"
  printf '%s\n' "$wrap" | sed 's/^/[mut] | /'
  if [[ "$wrap_rc" -eq 0 ]]; then
    echo "FAIL: gate passed with wrapped private phrase" >&2
    fails=$((fails+1))
  elif [[ "$wrap" != *"docs/wrap-residue.md:"* ]]; then
    echo "FAIL: wrap hit missing file:line" >&2
    fails=$((fails+1))
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
  echo "FAIL: mutation did not apply: docs/visible-residue.md" >&2
  fails=$((fails+1))
else
  hit="$(cd "$tmp/repo" && "./tests/$gate_name" 2>&1 || true)"
  if [[ "$hit" == *"docs/visible-residue.md:1:"* ]]; then
    echo "PASS: hit carries file:line"
  else
    printf '%s\n' "$hit" | sed 's/^/[mut] | /'
    echo "FAIL: hit missing file:line" >&2
    fails=$((fails+1))
  fi
fi
git -C "$tmp/repo" rm -q --cached docs/visible-residue.md 2>/dev/null || true
rm -f "$tmp/repo/docs/visible-residue.md"

# 6. Clean tree again after mutations are removed.
run_gate
if [[ "$GATE_RC" -eq 0 ]]; then
  echo "PASS: clean tree passes the gate after mutations"
else
  echo "FAIL: gate fails on a clean tree after mutations" >&2
  fails=$((fails+1))
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
    set +e
    VOCAB_MUT_SKIP_WORKTREE_SMOKE=1 "$wt/tests/$self_name" >/dev/null 2>&1
    wt_rc=$?
    set -e
    git -C "$root" worktree remove --force "$wt" >/dev/null 2>&1 || rm -rf "$wt"
    wt=""
    after_wt="$(git -C "$root" status --porcelain)"
    if [[ "$wt_rc" -ne 0 ]]; then
      echo "FAIL: linked-worktree smoke: harness rc=$wt_rc" >&2
      fails=$((fails+1))
    elif [[ "$after_wt" != "$before" ]]; then
      echo "FAIL: linked-worktree smoke mutated source index" >&2
      fails=$((fails+1))
    else
      echo "PASS: linked-worktree smoke (source index unchanged)"
    fi
  else
    echo "FAIL: linked-worktree smoke: git worktree add failed" >&2
    fails=$((fails+1))
    rm -rf "$wt"
    wt=""
  fi
fi

after="$(git -C "$root" status --porcelain)"
if [[ "$after" == "$before" ]]; then
  echo "PASS: real worktree/index untouched by harness"
else
  echo "FAIL: worktree/index changed by harness:" >&2
  diff <(printf '%s\n' "$before") <(printf '%s\n' "$after") >&2 || true
  fails=$((fails+1))
fi
if printf '%s\n' "$after" | grep -q "residue"; then
  echo "FAIL: residue path present in real worktree status" >&2
  fails=$((fails+1))
fi

if [[ "$fails" -ne 0 ]]; then
  echo "vocabulary-gate mutation: FAIL ($fails)" >&2
  exit 1
fi
echo "vocabulary-gate mutation: PASS"
exit 0
