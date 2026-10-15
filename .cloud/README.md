# Cloud environment and local steering

- `environment.json` records the cloud checkout, environment, GitHub remote, and
  shared branch. It is a reference, not runtime configuration.
- `.cloud/AGENTS.md` contains cloud workflow instructions and ends with a file
  reference to the repository's root `AGENTS.md`.
- The root `AGENTS.md` is your editable local steering. Cloud Codex reads it
  directly; there are no copied instructions or synchronization scripts.

Edit `AGENTS.md` locally, commit, and push to `codex/swift`. On the next cloud task,
Codex fetches your changes, reads the current file, and acknowledges new steering.
Uncommitted or unpushed local changes are not visible in the cloud, and a push
alone does not wake an idle chat.

Pull `codex/swift` locally to receive cloud changes. Codex has standing permission
to commit and push completed cloud work on this branch. Preserve both sides' work
when reconciling changes; do not discard local edits to make a pull succeed.

Detailed app behavior remains in `docs/APP_RULES.md`.
