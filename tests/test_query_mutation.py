"""Prove query regressions are caught in disposable copies, never the worktree."""
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
CASES = (
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
    "file-nofollow-removed": "test_leaf_open_refuses_swapped_symlink_before_opening_target",
    "root-symlink-check-removed": "test_symlink_ancestor_has_specific_refusal",
    "leaf-binding-type-check-removed": "test_leaf_binding_type_guard_rejects_symlink_before_open",
    "opened-leaf-type-check-removed": "test_opened_leaf_type_guard_rejects_swapped_fifo_before_header",
    "compat-as-default": "test_empty_and_scope",
    "archive-silently-ignored": "test_archive_is_refused_not_read",
    "body-read": "test_body_is_not_requested",
}


def run(root):
    return subprocess.run([sys.executable, "-B", str(root / "tests/test_query.py")],
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
            shutil.copy2(ROOT / "tests/test_query.py", copy / "tests/test_query.py")
            shutil.copy2(ROOT / "VERSION", copy / "VERSION")
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
