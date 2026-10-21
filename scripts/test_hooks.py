import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest import mock
import contextlib
import io


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

    def test_installer_backs_up_settings_and_preserves_existing_hooks(self):
        with tempfile.TemporaryDirectory() as root:
            home = Path(root)
            folder = home / ".claude"
            folder.mkdir()
            target = folder / "settings.json"
            original = '{"model":"keep","hooks":{"Stop":[{"hooks":[{"type":"command","command":"existing"}]}]}}'
            target.write_text(original)
            with mock.patch.object(Path, "home", return_value=home), mock.patch.object(setup.sys, "argv", ["setup-claude.py"]), contextlib.redirect_stdout(io.StringIO()):
                setup.main()
            self.assertEqual(next(folder.glob("settings.json.pulse-*.bak")).read_text(), original)
            settings = json.loads(target.read_text())
            self.assertEqual(settings["model"], "keep")
            self.assertEqual(settings["hooks"]["Stop"][0]["hooks"][0]["command"], "existing")
            self.assertTrue((home / ".local/share/pulse/claude-hook.py").exists())
            self.assertIn("UserPromptSubmit", settings["hooks"])

    def test_installer_refuses_malformed_settings_without_changing_them(self):
        with tempfile.TemporaryDirectory() as root:
            home = Path(root)
            folder = home / ".claude"
            folder.mkdir()
            target = folder / "settings.json"
            target.write_text("{broken")
            with mock.patch.object(Path, "home", return_value=home), mock.patch.object(setup.sys, "argv", ["setup-claude.py"]):
                with self.assertRaises(json.JSONDecodeError):
                    setup.main()
            self.assertEqual(target.read_text(), "{broken")

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
