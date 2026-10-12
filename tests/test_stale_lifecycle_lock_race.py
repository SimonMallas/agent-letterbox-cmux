#!/usr/bin/env python3
"""Race two terminal replies on a scratch request with a planted stale lock."""
import os
from pathlib import Path
import subprocess
import tempfile

CLI = Path(__file__).resolve().parents[1] / "bin" / "letterbox"
TRIALS = int(os.environ.get("LETTERBOX_LOCK_RACE_TRIALS", "64"))


def call(args, env, body=None):
    return subprocess.run([str(CLI), *args], input=body, text=True,
                          capture_output=True, env=env, timeout=15)


def main():
    errors = 0
    with tempfile.TemporaryDirectory(prefix="letterbox-stale-race-") as scratch:
        for trial in range(TRIALS):
            root = Path(scratch) / str(trial)
            env = os.environ.copy()
            env.pop("LETTERBOX_DOORBELL", None)  # never target an agent pane
            env.update(LETTERBOX_DIR=str(root), LETTERBOX_AGENT="sender")
            init = call(["init", "sender", "recipient"], env)
            assert init.returncode == 0, init.stderr
            sent = call(["send", "recipient", "request", "task", "--ack"], env, "task\n")
            assert sent.returncode == 0, sent.stderr
            letter, = (root / "recipient/inbox").glob("*.md")
            lock = Path(str(letter) + ".lifecycle.lock")
            lock.mkdir()
            (lock / "pid").write_text("99999999\n")
            env["LETTERBOX_AGENT"] = "recipient"
            pair = [subprocess.Popen([str(CLI), "reply", letter.stem, action, "done"],
                                     stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                     stderr=subprocess.PIPE, text=True, env=env)
                    for action in ("result", "nack")]
            # Start both closers before waiting for either: sequential communicate()
            # accidentally serializes the race when a reply first reads stdin.
            for process in pair:
                process.stdin.write("done\n")
                process.stdin.close()
                process.stdin = None
            outcomes = [process.communicate(timeout=15) for process in pair]
            for process, (_, stderr) in zip(pair, outcomes):
                if process.returncode and "/pid: No such file or directory" in stderr:
                    errors += 1
            published = (list((root / "sender/inbox").glob("*--recipient--result.md"))
                         + list((root / "sender/inbox").glob("*--recipient--nack.md")))
            assert len(published) == 1, (trial, len(published), outcomes)
            assert errors == 0, (trial, "stale breaker deleted a new lock", outcomes)
    print(f"stale lifecycle lock race: PASS ({TRIALS} trials, 0 pid-write errors, 1 terminal reply each)")


if __name__ == "__main__":
    main()
