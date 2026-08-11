#!/usr/bin/env bash
# test_no_private_data.sh — public-release hygiene gate.
#
# Fails if tracked files contain local machine paths or secret-shaped strings.
# Ships with GENERIC patterns only. Team/machine-specific identity strings do NOT
# belong in a public repo (a scan that names the names leaks the names): put them in
#   tests/private-patterns.local   (gitignored; one extended regex per line; HARD)
# Silence intended public mentions with
#   .public-allowlist              (gitignored; one grep -F line-filter per line)
# This script, the override, and the allowlist are excluded from the scan.
set -uo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"; cd "$root"
self="tests/$(basename "$0")"
allow="$root/.public-allowlist"
override="$root/tests/private-patterns.local"

files="$(git ls-files | grep -v -e "^$self\$" -e '^\.public-allowlist$' -e '^tests/private-patterns\.local$')"
[[ -n "$files" ]] || { echo "no-private-data: no tracked files?" >&2; exit 1; }

fails=0
report() { # $1 label, $2 grep output
  [[ -z "$2" ]] && return 0
  printf 'FAIL [%s] private data:\n%s\n' "$1" "$2" >&2
  fails=$((fails + 1))
}
scan() { # $1 label, $2 grep-flags, $3 pattern, $4 optional exclusion regex
  local out
  out="$(printf '%s\n' "$files" | xargs grep -nI $2 -e "$3" 2>/dev/null || true)"
  if [[ -n "$out" && -n "${4:-}" ]]; then
    out="$(printf '%s\n' "$out" | grep -vE "$4" || true)"
  fi
  if [[ -n "$out" && -f "$allow" ]]; then
    out="$(printf '%s\n' "$out" | grep -vFf "$allow" || true)"
  fi
  report "$1" "$out"
}

# Local machine paths. Placeholder usernames (you/your/user/username/name/me/whoami)
# are documentation idioms, not leaks — excluded to keep a shipped clean tree green.
scan "abs-user-path" -inE '/(Users|home)/[A-Za-z0-9._-]+/' '/(Users|home)/(you|your|user|username|name|me|whoami)/'
scan "mount-path"    -inE '/(Volumes|mnt|media)/[A-Za-z0-9._-]+'
# Secret shapes (length floors avoid code identifiers like skill_target)
scan "api-keys"      -nE '(sk-[A-Za-z0-9_-]{16,}|gh[opu]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|xox[bap]-[A-Za-z0-9-]{10,}|AKIA[0-9A-Z]{16})'
scan "private-key"   -nF 'PRIVATE KEY-----'
scan "bot-token"     -nE '[0-9]{8,12}:[A-Za-z0-9_-]{30,}'

# Optional team-local HARD patterns (never shipped; see header).
# Output must always state whether this override was in effect, so CI logs
# never imply team-private identity coverage that was not configured.
override_state="ABSENT — generic patterns only (no team-private identity coverage)"
if [[ -f "$override" ]]; then
  override_count=0
  while IFS= read -r pat || [[ -n "$pat" ]]; do
    [[ -z "$pat" || "$pat" == \#* ]] && continue
    override_count=$((override_count + 1))
    scan "local-override" -inE "$pat"
  done < "$override"
  if (( override_count > 0 )); then
    override_state="ACTIVE ($override_count local pattern(s) from tests/private-patterns.local)"
  else
    override_state="ABSENT — override file present but no usable patterns (generic coverage only)"
  fi
fi
printf 'no-private-data: override %s\n' "$override_state"

if (( fails > 0 )); then
  printf 'no-private-data: FAIL (%d pattern groups hit, override %s)\n' "$fails" "$override_state" >&2
  exit 1
fi
printf 'no-private-data: PASS\n'
