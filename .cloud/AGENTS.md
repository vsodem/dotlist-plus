# Cloud repository instructions

Read `.cloud/environment.json` for the recorded cloud environment and checkout.
The current checkout is `/workspace/dotlist-plus` in a managed Linux environment.
The shared branch is `codex/swift` in `vsodem/dotlist-plus`. Paths and environment
IDs are reference snapshots; verify them in new sessions.

At the start of cloud work, inspect the working tree and fetch
`origin/codex/swift`. Read and incorporate incoming changes without discarding
unfinished work. Acknowledge newly received user steering in chat. Check for
incoming changes again before pushing, and preserve work from both environments.
If fetching fails, explain that the latest local changes could not be checked.

Commit and push completed cloud changes on `codex/swift` under the user's standing
authorization. Local changes become available here after they are committed and
pushed; this is not live filesystem sync and does not automatically wake a chat.

Shared Swift tests can run on Linux with an installed toolchain. Apple builds,
simulators, and signing require Xcode on macOS. Tools under `/tmp` are temporary.

Always read the repository instructions directly from the file referenced below.
Do not copy or append their contents here. Reread that file after incoming changes
or edits so its current instructions are used. Its local steering takes precedence
over conflicting cloud defaults; current chat instructions take precedence over
repo notes. These instructions apply repository-wide when read from root AGENTS.md.

[Repository instructions](../AGENTS.md)
