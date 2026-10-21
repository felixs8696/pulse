#!/usr/bin/python3
"""Merge hooks without replacing any existing commands. --remove reverses our entries."""
import datetime
import json
import os
from pathlib import Path
import shlex
import shutil
import sys
import tempfile

EVENTS = ("SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse", "PermissionRequest", "Notification", "Stop", "StopFailure", "SessionEnd")
MARKER = "pulse/claude-hook.py"


def merge(settings, command, remove=False):
    hooks = settings.setdefault("hooks", {})
    for event in EVENTS:
        groups = hooks.get(event, [])
        cleaned = []
        for group in groups:
            remaining = [h for h in group.get("hooks", []) if MARKER not in h.get("command", "")]
            if remaining:
                cleaned.append(dict(group, hooks=remaining))
        if not remove:
            cleaned.append({"matcher": "*", "hooks": [{"type": "command", "command": command, "timeout": 3}]})
        if cleaned:
            hooks[event] = cleaned
        else:
            hooks.pop(event, None)
    return settings


def main():
    root = Path.home() / ".claude"
    root.mkdir(parents=True, exist_ok=True)
    settings_file = root / "settings.json"
    raw = settings_file.read_text() if settings_file.exists() else "{}"
    settings = json.loads(raw)  # Refuse to rewrite malformed settings.
    remove = "--remove" in sys.argv
    install = Path.home() / ".local/share/pulse"
    if not remove:
        install.mkdir(mode=0o700, parents=True, exist_ok=True)
        shutil.copy2(Path(__file__).with_name("claude-hook.py"), install / "claude-hook.py")
    command = "/usr/bin/python3 " + shlex.quote(str(install / "claude-hook.py"))
    merge(settings, command, remove)
    if settings_file.exists():
        backup = settings_file.with_name("settings.json.pulse-" + datetime.datetime.now().strftime("%Y%m%d-%H%M%S-%f") + ".bak")
        shutil.copy2(settings_file, backup)
        print("Backed up settings to", backup)
    descriptor, temp = tempfile.mkstemp(dir=str(root), prefix=".pulse-")
    with os.fdopen(descriptor, "w") as handle:
        json.dump(settings, handle, indent=2)
        handle.write("\n")
    os.replace(temp, settings_file)
    print("Pulse hooks removed." if remove else "Pulse hooks enabled. New Claude sessions will report exact attention states and iTerm pane IDs.")


if __name__ == "__main__":
    main()
