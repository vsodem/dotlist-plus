# Repository instructions

## GitHub is the source of truth

These rules apply only to this project. The canonical version is GitHub's
`origin/codex/swift`. Work is not complete until its changes are committed,
pushed to that branch, and verified against GitHub.

At the very beginning of every chat, when resuming after inactivity, and
before executing any new request, perform this check before modifying files:

1. Inspect the current branch and local changes, then run
   `git fetch origin codex/swift`. Do not rely on a stale remote reference.
2. Ensure local `HEAD` matches `origin/codex/swift`. If it is behind, run
   `git merge --ff-only origin/codex/swift`, preserving local changes, and
   verify that the commits now match before proceeding.
3. Immediately report any check or sync error and pause file modifications
   until it is resolved. If local commits are ahead, inspect and validate them,
   then push completed project work using the finish steps below. If commits
   have diverged or local changes prevent syncing, report the mismatch and
   stop before further edits. Never discard local work or force-push.

Before ending each task or chat:

1. Review the diff and run checks appropriate to the changes. Stage the task's
   files explicitly, then commit them. Do not bundle unrelated local changes.
2. Run `git fetch origin codex/swift` again. If GitHub has changes not included
   locally, report the mismatch immediately and resolve it without overwriting
   either side before pushing. Never claim completion while this is unresolved.
3. Push completed commits with `git push origin HEAD:refs/heads/codex/swift`.
   This project's standing instructions authorize committing and pushing
   completed work; no additional confirmation is needed for those actions.
4. Compare `git rev-parse HEAD` with
   `git ls-remote --exit-code origin refs/heads/codex/swift` and inspect
   `git status --short`. Only report the work as published when the commits
   match. Report any remaining local files that are not on GitHub explicitly.
5. Report commit, push, network, authentication, or verification failures
   immediately. Preserve the work and clearly state that publishing is
   incomplete; do not silently leave commits only on the local computer.

Project hooks in `.codex/hooks.json` repeat the start check on every new prompt
(including returns after inactivity), and check GitHub and local changes at
the end of each turn. They require Codex's one-time hook trust review via
`/hooks` in the CLI. Until trusted, follow these instructions manually.
The finish hook requests one corrective pass; if still blocked, it reports
publishing as incomplete instead of looping or hiding the failure.

Use `docs/APP_RULES.md` as the editable behavior specification. Update the
relevant rules and acceptance checks together when changing behavior.
