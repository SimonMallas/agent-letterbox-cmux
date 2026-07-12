"""Mock-backed test for the macOS desktop adapter."""
import os
import subprocess
import tempfile
from pathlib import Path

def test_desktop_adapter_runs_with_mock(monkeypatch):
    """Ensure the adapter executes without real osascript calls."""
    calls = []

    def fake_osascript(*args, **kwargs):
        calls.append(args)
        return subprocess.CompletedProcess(args, 0, stdout=b"", stderr=b"")

    monkeypatch.setattr(subprocess, "run", fake_osascript)
    monkeypatch.setenv("LETTERBOX_MACOS_APP", "Hermes")
    monkeypatch.setenv("LETTERBOX_DIR", "/tmp/letterbox")

    adapter = Path(__file__).parent.parent / "adapters" / "desktop.sh"
    result = subprocess.run(
        ["bash", str(adapter), "pi", "delegate", "test-slug"],
        capture_output=True,
        text=True,
    )

    assert result.returncode == 0
    assert "desktop notification + activation attempted" in result.stdout
    assert len(calls) >= 1  # at least notification was attempted
