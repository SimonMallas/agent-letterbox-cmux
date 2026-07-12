"""Substantive fixture test covering frontmatter + all hardened rules."""
import pathlib
import re

def test_skill_has_valid_frontmatter_and_rules():
    skill = pathlib.Path(__file__).parent.parent / "integrations/hermes/skills/agent-letterbox/SKILL.md"
    content = skill.read_text()

    # Frontmatter assertions
    assert content.startswith("---")
    assert "name: agent-letterbox" in content
    assert "prerequisites:" in content and "commands: [letterbox]" in content
    assert "version:" in content and "author:" in content

    # Rule 1
    assert "letterbox check" in content and "LETTERBOX_DIR" in content and "LETTERBOX_AGENT" in content

    # Rule 2
    assert "letterbox reply <id> <ack|nack|result> <slug>" in content

    # Rule 3
    assert "Re-run check after every reply" in content
    assert "proves replied + archived" in content

    # Rule 4
    assert "explicitly report failure" in content
    assert "blocker" in content.lower()

    # Rule 5
    assert "untrusted" in content.lower()

    # Rule 6
    assert "non-actionable" in content.lower() or "archive-only primitive" in content.lower()

if __name__ == "__main__":
    test_skill_has_valid_frontmatter_and_rules()
    print("skill fixture: PASS")
