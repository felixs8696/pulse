import importlib.util
import json
from pathlib import Path
import tempfile
import unittest


def load(name):
    spec = importlib.util.spec_from_file_location(name, Path(__file__).with_name(name + ".py"))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


hook = load("claude-hook")
setup = load("setup-claude")


class HookTests(unittest.TestCase):
    def test_merge_is_idempotent_and_preserves_other_hooks(self):
        settings = {"model": "keep", "hooks": {"Stop": [{"hooks": [{"type": "command", "command": "existing"}]}]}}
        command = "/usr/bin/python3 '/tmp/pulse/claude-hook.py'"
        setup.merge(settings, command)
        first = json.dumps(settings, sort_keys=True)
        setup.merge(settings, command)
        self.assertEqual(json.dumps(settings, sort_keys=True), first)
        setup.merge(settings, command, remove=True)
        self.assertEqual(settings["hooks"]["Stop"][0]["hooks"][0]["command"], "existing")
        self.assertEqual(settings["model"], "keep")

    def test_event_state_and_terminal_capture(self):
        with tempfile.TemporaryDirectory() as root:
            environment = {"ITERM_SESSION_ID": "w1t2p0:ABC"}
            for event, expected in [("UserPromptSubmit", "running"), ("PermissionRequest", "waiting"), ("Stop", "ready"), ("SessionEnd", "ended")]:
                hook.record({"session_id": "test-id", "hook_event_name": event, "cwd": "/tmp"}, environment, root, host={})
                state = json.loads((Path(root) / "test-id.json").read_text())
                self.assertEqual(state["state"], expected)
                self.assertEqual(state["iterm_session_id"], "w1t2p0:ABC")

    def test_cursor_host_clears_inherited_iterm_id(self):
        with tempfile.TemporaryDirectory() as root:
            hook.record({"session_id": "cursor-id", "hook_event_name": "Stop"},
                        {"ITERM_SESSION_ID": "stale-pane"}, root,
                        host={"host_bundle_id": "com.todesktop.230313mzl4w4u92", "host_surface": "claudePanel"})
            state = json.loads((Path(root) / "cursor-id.json").read_text())
            self.assertEqual(state["iterm_session_id"], "")
            self.assertEqual(state["host_surface"], "claudePanel")

    def test_unknown_notifications_and_bad_ids_do_not_create_events(self):
        with tempfile.TemporaryDirectory() as root:
            hook.record({"session_id": "../escape", "hook_event_name": "Stop"}, {}, root)
            hook.record({"session_id": "test", "hook_event_name": "Notification", "notification_type": "unrelated"}, {}, root)
            self.assertEqual(list(Path(root).iterdir()), [])


if __name__ == "__main__":
    unittest.main()
