"""Prove query regressions are caught in disposable copies, never the worktree."""
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
CASES = (
    ("slug-budget-removed", "bin/letterbox",
     '(( ${#slug} <= max_slug )) || die "slug too long: max $max_slug characters for this sender/recipient/type"', ':'),
    ("strict-legacy-id-cap-regressed", "lib/query/strict.py",
     'LETTER_ID = re.compile(r"[A-Za-z0-9_.:-]{1,243}")',
     'LETTER_ID = re.compile(r"[A-Za-z0-9_.:-]{1,128}")'),
    ("compat-legacy-id-cap-regressed", "lib/query/envelopes.py",
     'LETTER_ID = re.compile(r"[A-Za-z0-9_.:-]{1,243}")',
     'LETTER_ID = re.compile(r"[A-Za-z0-9_.:-]{1,128}")'),
    ("re-validation-removed", "bin/letterbox",
     '[[ -z "$re" ]] || validate_relation_id re "$re"', ':'),
    ("deadline-validation-removed", "bin/letterbox",
     '[[ -z "$deadline" ]] || validate_utc deadline "$deadline"', ':'),
    ("session-validation-removed", "bin/letterbox",
     '[[ -z "$SESSION" || "$SESSION" =~ ^[A-Za-z0-9._:-]{1,64}$ ]]', ':'),
    ("send-clock-validation-removed", "bin/letterbox",
     '  validate_utc sent "$sent"\n  id=', '  id='),
    ("reply-clock-validation-removed", "bin/letterbox",
     '  validate_utc sent "$sent"\n  tmp=', '  tmp='),
    ("generated-id-validation-removed", "bin/letterbox",
     '  validate_relation_id id "$id"', '  :'),
    ("reply-prelock-validation-removed", "bin/letterbox",
     '  validate_reply_metadata "$parent_id" "$doorbell_to" "$parent_thread" "$type"', '  :'),
    ("send-sent-removed", "bin/letterbox",
     "printf 'id: %s\\nsent: %s\\nfrom: %s\\nto: %s\\ntype: %s\\nre: %s\\n'",
     "printf 'id: %s\\nstamp: %s\\nfrom: %s\\nto: %s\\ntype: %s\\nre: %s\\n'"),
    ("reply-sent-removed", "bin/letterbox",
     "printf 'id: %s\\nsent: %s\\nfrom: %s\\nto: %s\\ntype: %s\\nre: %s\\nthread: %s\\n",
     "printf 'id: %s\\nstamp: %s\\nfrom: %s\\nto: %s\\ntype: %s\\nre: %s\\nthread: %s\\n"),
    ("split-publication-clock", "bin/letterbox",
     '  id="${sent//:/}"\n  id="${id%Z}-$ME-$type-$slug-$(random_suffix)"',
     '  id="$(id_now)-$ME-$type-$slug-$(random_suffix)"'),
    ("reference-validation-removed", "bin/letterbox",
     '[[ "$2" =~ ^[A-Za-z0-9._:-]+$ && ${#2} -le $MAX_LETTER_ID ]]', ':'),
    ("file-nofollow-removed", "lib/query/scanner.py",
     'FILE_FLAGS = os.O_RDONLY | os.O_CLOEXEC | os.O_NOFOLLOW | os.O_NONBLOCK',
     'FILE_FLAGS = os.O_RDONLY | os.O_CLOEXEC | os.O_NONBLOCK'),
    ("root-symlink-check-removed", "lib/query/scope.py",
     '            if stat.S_ISLNK(binding.st_mode):\n'
     '                refusal_code = "root_component_symlink"\n'
     '                raise OSError("symlink root component")\n', ''),
    ("leaf-binding-type-check-removed", "lib/query/scanner.py",
     'if not stat.S_ISREG(binding.st_mode):\n                    issue = "unsafe_leaf"',
     'if False:\n                    issue = "unsafe_leaf"'),
    ("opened-leaf-type-check-removed", "lib/query/scanner.py",
     'if not stat.S_ISREG(before.st_mode):\n                        issue = "unsafe_leaf"',
     'if False:\n                        issue = "unsafe_leaf"'),
    ("compat-as-default", "bin/letterbox",
     'if [[ "${1:-}" == --compat-v2 ]]; then', 'if true; then'),
    ("archive-silently-ignored", "lib/query/scanner.py",
     'self.issue(ref + "/archive", "unsupported_archive_layout")', 'pass'),
    ("body-read", "lib/query/envelopes.py",
     'if text == "---":\n            return fields',
     'if text == "---":\n            stream.readline()\n            return fields'),
)


WITNESSES = {
    "slug-budget-removed": "test_over_limit_slug_refused_before_any_write",
    "strict-legacy-id-cap-regressed": "test_legacy_long_id_reply_reference_and_query",
    "compat-legacy-id-cap-regressed": "test_legacy_long_id_reply_reference_and_query",
    "re-validation-removed": "test_legacy_header_inputs_refused_before_any_write",
    "deadline-validation-removed": "test_legacy_header_inputs_refused_before_any_write",
    "session-validation-removed": "test_invalid_session_refused_on_send_and_reply_before_write",
    "send-clock-validation-removed": "test_invalid_publication_clock_refused_without_letter",
    "reply-clock-validation-removed": "test_invalid_publication_clock_refused_without_letter",
    "generated-id-validation-removed": "test_generated_id_is_bounded_before_temp_creation",
    "reply-prelock-validation-removed": "test_inherited_reply_metadata_refused_before_lock",
    "send-sent-removed": "test_send_has_one_utc_snapshot_for_id_and_sent",
    "reply-sent-removed": "test_reply_own_time_parent_identity_and_retry_bytes",
    "split-publication-clock": "test_send_has_one_utc_snapshot_for_id_and_sent",
    "reference-validation-removed": "test_malformed_references_refuse_before_any_write",
    "file-nofollow-removed": "test_leaf_open_refuses_swapped_symlink_before_opening_target",
    "root-symlink-check-removed": "test_symlink_ancestor_has_specific_refusal",
    "leaf-binding-type-check-removed": "test_leaf_binding_type_guard_rejects_symlink_before_open",
    "opened-leaf-type-check-removed": "test_opened_leaf_type_guard_rejects_swapped_fifo_before_header",
    "compat-as-default": "test_empty_and_scope",
    "archive-silently-ignored": "test_archive_is_refused_not_read",
    "body-read": "test_body_is_not_requested",
}


def run(root):
    return subprocess.run([sys.executable, "-B", "-m", "unittest", "discover",
                           "-s", str(root / "tests"), "-p", "test_*query.py"],
                          capture_output=True, text=True, timeout=120)


def main():
    baseline = run(ROOT)
    if baseline.returncode:
        print(baseline.stdout + baseline.stderr)
        raise SystemExit("query mutation: healthy control failed")
    print("PASS: healthy query control")
    for name, relative, old, new in CASES:
        with tempfile.TemporaryDirectory() as tmp:
            copy = Path(tmp)
            for folder in ("bin", "lib", "adapters"):
                shutil.copytree(ROOT / folder, copy / folder)
            (copy / "tests").mkdir()
            shutil.copytree(ROOT / "tests/fixtures", copy / "tests/fixtures")
            for test_file in ("test_query.py", "test_writer_query.py"):
                shutil.copy2(ROOT / "tests" / test_file, copy / "tests" / test_file)
            shutil.copy2(ROOT / "VERSION", copy / "VERSION")
            shutil.copy2(ROOT / "README.md", copy / "README.md")
            target = copy / relative
            text = target.read_text()
            if text.count(old) != 1:
                raise SystemExit("query mutation: replacement anchor is not unique: " + name)
            target.write_text(text.replace(old, new))
            result = run(copy)
            # Reject syntax/import failures as proof: assertions must fail.
            if result.returncode == 0 or "FAIL: " + WITNESSES[name] + " (" not in result.stderr:
                print(result.stdout + result.stderr)
                raise SystemExit("query mutation: not caught by assertion: " + name)
            print("PASS: mutation caught: " + name)
    print("query mutation: PASS (%d/%d)" % (len(CASES), len(CASES)))


if __name__ == "__main__":
    main()
