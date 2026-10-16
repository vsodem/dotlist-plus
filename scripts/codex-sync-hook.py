"""Project-local Codex reminders and a read-only publication check."""

import json
import os
import subprocess
import sys


def handle(event):
    if event["hook_event_name"] in ("SessionStart", "UserPromptSubmit"):
        return {"hookSpecificOutput": {
            "hookEventName": event["hook_event_name"],
            "additionalContext": (
                "Follow this project's AGENTS.md GitHub rules now, before task work: "
                "run local inspection commands (git status, git diff, git rev-parse) "
                "inside the sandbox. When .git is protected, run fetch, staging, "
                "commit, merge, and push through exec_command with "
                'sandbox_permissions: "require_escalated" from the first attempt. '
                "Use that path for required network commands, including git ls-remote, "
                "when network access is restricted. Request access before these commands; "
                "do not first try a sandboxed Git write or restricted network call. "
                "If access is denied, preserve local work and report the blockage "
                "without repeating the same attempt. This does not grant permissions "
                "or disable sandbox or approval controls. Then "
                "inspect local changes, fetch origin/codex/swift, and safely sync. "
                "Report any error immediately before modifying files. This applies "
                "at chat startup and on every new prompt, including after inactivity. "
                "Before finishing, validate, commit and push completed work to "
                "origin/codex/swift, then verify GitHub matches HEAD."
            ),
        }}

    def git(*args):
        return subprocess.run(
            ["git", *args], cwd=event["cwd"], check=True,
            capture_output=True, text=True, timeout=20,
            env={**os.environ, "GIT_TERMINAL_PROMPT": "0"},
        ).stdout.strip()

    problems = []
    try:
        local = git("rev-parse", "HEAD")
        remote = git("ls-remote", "--exit-code", "origin", "refs/heads/codex/swift")
        if not remote or local != remote.split()[0]:
            problems.append("Local HEAD does not match GitHub's codex/swift branch.")
        changes = git("status", "--short", "--untracked-files=all")
        if changes:
            problems.append("Local files remain unpublished:\n" + changes)
    except (subprocess.SubprocessError, OSError) as error:
        detail = getattr(error, "stderr", None) or str(error)
        problems.append("GitHub verification failed: " + detail.strip())

    if not problems:
        return {}

    message = "Publishing is incomplete. " + "\n".join(problems)
    if event.get("stop_hook_active"):
        return {"continue": False, "stopReason": message, "systemMessage": message}
    return {
        "decision": "block",
        "reason": message + (
            "\nFollow AGENTS.md's finish steps: validate, commit and push this task's "
            "work, then verify GitHub. Preserve unrelated files and report them. "
            "If blocked, report the exact error and incomplete publication to the user. "
            "Do not force-push, discard work, or claim everything is published."
        ),
    }


if __name__ == "__main__":
    print(json.dumps(handle(json.load(sys.stdin))))
