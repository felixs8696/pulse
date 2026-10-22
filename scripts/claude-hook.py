#!/usr/bin/python3
"""Fast local Claude Code hook. Never emits text or blocks an agent on failure."""
import datetime
import json
import os
from pathlib import Path
import sys
import subprocess
import tempfile


def host_context(environment):
    # Inspect executable ancestry, not inherited ITERM_SESSION_ID (Cursor can inherit it).
    try:
        output = subprocess.run(['/bin/ps', '-axo', 'pid=,ppid=,comm='], capture_output=True, text=True, timeout=1).stdout
        processes = {}
        for line in output.splitlines():
            parts = line.strip().split(None, 2)
            if len(parts) == 3:
                processes[int(parts[0])] = (int(parts[1]), parts[2])
        pid = os.getppid()
        ancestors = []
        panel = environment.get('CLAUDE_CODE_ENTRYPOINT') == 'claude-vscode'
        while pid in processes and pid not in ancestors and len(ancestors) < 30:
            ancestors.append(pid)
            parent, executable = processes[pid]
            panel = panel or '/anthropic.claude-code-' in executable
            if '/Claude.app/' in executable:
                return {'host_bundle_id': 'com.anthropic.claudefordesktop', 'host_surface': 'code'}
            if '/Cursor.app/' in executable:
                return {'host_bundle_id': 'com.todesktop.230313mzl4w4u92',
                        'host_surface': 'claudePanel' if panel else 'terminal', 'terminal_ancestor_pids': ancestors}
            if '/iTerm.app/' in executable or '/iTerm2.app/' in executable:
                return {'host_bundle_id': 'com.googlecode.iterm2', 'host_surface': 'terminal'}
            pid = parent
    except (OSError, ValueError, subprocess.TimeoutExpired):
        pass
    return {}


def record(event, environment=None, directory=None, host=None):
    environment = os.environ if environment is None else environment
    host = host_context(environment) if host is None else host
    session_id = event.get("session_id", "")
    if not session_id or any(c not in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_" for c in session_id):
        return
    root = Path(directory) if directory else Path.home() / ".local/share/pulse/events"
    root.mkdir(mode=0o700, parents=True, exist_ok=True)
    target = root / (session_id + ".json")
    try:
        previous = json.loads(target.read_text())
    except (OSError, ValueError):
        previous = {}
    name = event.get("hook_event_name", "")
    states = {"SessionStart": "idle", "UserPromptSubmit": "running", "PreToolUse": "running",
              "PostToolUse": "running", "PermissionRequest": "waiting", "Stop": "ready", "StopFailure": "waiting", "SessionEnd": "ended"}
    state = states.get(name)
    if name == "PreToolUse" and event.get("tool_name") in ("AskUserQuestion", "ExitPlanMode"):
        state = "waiting"
    if name == "Notification":
        if event.get("notification_type") in ("permission_prompt", "idle_prompt", "elicitation_dialog"):
            state = "waiting"
        else:
            return
    if state is None:
        return
    now = datetime.datetime.now(datetime.timezone.utc).isoformat()
    data = {"session_id": session_id, "state": state, "updated_at": now,
            "state_since": previous.get("state_since", now) if previous.get("state") == state else now,
            "cwd": event.get("cwd", previous.get("cwd", "")),
            "iterm_session_id": environment.get("ITERM_SESSION_ID", previous.get("iterm_session_id", "")),
            "transcript_path": event.get("transcript_path", ""), "owner_pid": os.getppid()}
    data.update(host)
    if host.get('host_bundle_id') in ('com.todesktop.230313mzl4w4u92', 'com.anthropic.claudefordesktop'):
        data['iterm_session_id'] = ''
    # The hook's immediate parent may be a shell, so the scanner does not treat it as the Claude owner.
    data.pop("owner_pid")
    descriptor, temp = tempfile.mkstemp(dir=str(root), prefix=".event-")
    try:
        with os.fdopen(descriptor, "w") as handle:
            json.dump(data, handle)
        os.replace(temp, target)
    finally:
        if os.path.exists(temp):
            os.unlink(temp)


if __name__ == "__main__":
    try:
        record(json.load(sys.stdin))
    except Exception:
        pass
