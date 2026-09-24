"""Prove query regressions are caught in disposable copies, never the worktree."""
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
CASES = (
    ("compat-as-default", "bin/letterbox",
     'if [[ "${1:-}" == --compat-v2 ]]; then', 'if true; then'),
    ("archive-silently-ignored", "lib/query/scanner.py",
     'self.issue(ref + "/archive", "unsupported_archive_layout")', 'pass'),
    ("body-read", "lib/query/envelopes.py",
     'if text == "---":\n            return fields',
     'if text == "---":\n            stream.readline()\n            return fields'),
)


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
            if result.returncode == 0 or "FAIL:" not in result.stderr:
                print(result.stdout + result.stderr)
                raise SystemExit("query mutation: not caught by assertion: " + name)
            print("PASS: mutation caught: " + name)
    print("query mutation: PASS (3/3)")


if __name__ == "__main__":
    main()
