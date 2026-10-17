import importlib.util
import pathlib
import subprocess
import tempfile
import unittest
from unittest.mock import patch


SCRIPT = pathlib.Path(__file__).with_name("codex-sync-hook.py")


class SyncHookTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = pathlib.Path(self.temp.name)
        self.remote = self.root / "remote.git"
        self.repo = self.root / "repo"
        self.git(self.root, "init", "--bare", str(self.remote))
        self.git(self.root, "clone", str(self.remote), str(self.repo))
        self.git(self.repo, "checkout", "-B", "main")
        self.git(self.repo, "config", "user.name", "Hook Test")
        self.git(self.repo, "config", "user.email", "hook@example.test")
        (self.repo / "file.txt").write_text("initial\n")
        self.git(self.repo, "add", "file.txt")
        self.git(self.repo, "commit", "-m", "Initial")
        self.git(self.repo, "push", "origin", "main")

    def git(self, cwd, *args):
        return subprocess.run(
            ["git", "-C", str(cwd), *args], check=True,
            capture_output=True, text=True,
        ).stdout.strip()

    def check(self, **event):
        self.assertTrue(SCRIPT.exists(), "Sync hook has not been implemented")
        spec = importlib.util.spec_from_file_location("sync_hook", SCRIPT)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        return module.handle({"hook_event_name": "Stop", "cwd": str(self.repo), **event})

    def test_clean_pushed_repository_can_finish(self):
        self.assertEqual(self.check(), {})

    def test_unpushed_commit_blocks_completion(self):
        self.git(self.repo, "commit", "--allow-empty", "-m", "Unpushed")
        result = self.check()
        self.assertEqual(result["decision"], "block")
        self.assertIn("GitHub", result["reason"])

    def test_tracked_and_untracked_changes_block_completion(self):
        for name in ("file.txt", "new.txt"):
            with self.subTest(name=name):
                path = self.repo / name
                path.write_text("changed\n")
                result = self.check()
                self.assertEqual(result["decision"], "block")
                self.assertIn(name, result["reason"])

    def test_unreachable_remote_is_reported(self):
        self.git(self.repo, "remote", "set-url", "origin", str(self.root / "missing.git"))
        result = self.check()
        self.assertEqual(result["decision"], "block")
        self.assertIn("failed", result["reason"])

    def test_remote_change_is_detected_without_a_local_fetch(self):
        other = self.root / "other"
        self.git(self.root, "clone", "-b", "main", str(self.remote), str(other))
        self.git(other, "-c", "user.name=Hook Test", "-c", "user.email=hook@example.test",
                 "commit", "--allow-empty", "-m", "Remote update")
        self.git(other, "push", "origin", "main")
        result = self.check()
        self.assertEqual(result["decision"], "block")
        self.assertIn("GitHub", result["reason"])

    def test_repeated_failure_reports_incomplete_without_looping(self):
        (self.repo / "file.txt").write_text("changed\n")
        result = self.check(stop_hook_active=True)
        self.assertFalse(result["continue"])
        self.assertIn("incomplete", result["systemMessage"])

    def test_start_and_resume_prompt_require_sync_before_edits(self):
        for event in ("SessionStart", "UserPromptSubmit"):
            with self.subTest(event=event):
                result = self.check(hook_event_name=event)
                self.assertEqual(result["hookSpecificOutput"]["hookEventName"], event)
                self.assertIn("before", result["hookSpecificOutput"]["additionalContext"])

    def test_startup_requires_access_before_first_git_write(self):
        for event in ("SessionStart", "UserPromptSubmit"):
            with self.subTest(event=event):
                context = self.check(hook_event_name=event)["hookSpecificOutput"]["additionalContext"]
                for instruction in (
                    "local inspection commands", "inside the sandbox", ".git is protected",
                    "fetch", "staging", "commit", "merge", "push", "exec_command",
                    'sandbox_permissions: "require_escalated"', "from the first attempt",
                    "network access is restricted", "access is denied", "preserve local work",
                    "report the blockage", "without repeating the same attempt",
                ):
                    self.assertIn(instruction, context)

    def test_startup_never_runs_subprocesses(self):
        with patch("subprocess.run", side_effect=AssertionError("Startup must not run commands")) as run:
            for event in ("SessionStart", "UserPromptSubmit"):
                with self.subTest(event=event):
                    result = self.check(hook_event_name=event)
                    self.assertEqual(result["hookSpecificOutput"]["hookEventName"], event)
            run.assert_not_called()


if __name__ == "__main__":
    unittest.main()
