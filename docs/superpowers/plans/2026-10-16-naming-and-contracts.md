1. Preserve rules while renaming Swift declarations, serialized fields, UI language, tests and paths; split Core, Application, Storage, CloudKit, UI and link package products from the thin app. Check baseline and renamed tests.
2. Generate identity from product-identity.json; add strict versioned FormatEnvelope coding, separate portable and recovery formats, remove migration and block incompatible stores/cloud uploads. Test old rejection, no writes, restart and round trips.
3. Verify relationships and coordinator transactions, cancellation, conflicts and explicit complete-list resolution; keep provider events in application commands. Test invalid merge retention and conditional resolution.
4. Retire browser files/workflow, replace contradictory docs and label history; enforce naming, dependencies, Xcode membership and non-writing generation checks with negative tests.
5. Run Swift/hook/checker tests and both unsigned Apple builds; inspect UI names, independent review, commit task files, fetch, push and verify SHA. Signing and two-device checks remain release work.

## Completion record — 2026-10-16

The five steps are implemented. The package exposes Core, Application, Storage, CloudKit and UI with the documented dependency graph. The thin app links products. New identity and strict envelopes replace the previous formats without migration or discovery. Browser entry points and the explicitly authorized Playwright workflow are removed; `.codex/hooks.json` is unchanged.

Review fixes:
- Reject production target declarations the dependency checker cannot parse, including custom `path:` declarations; covered by a negative test.
- Capture the list and account shown when import/erase confirmation begins. Reject replacement/erasure after unseen edits; covered by coordinator tests.
- Use the internal CloudKit codec in the actual adapter. Apple tests reject incompatible payloads/record metadata before preparing an upload or changing asset bytes.
- Restrict UI-only store properties and batch editing to the UI module. Keep only the app's required state, commands and entry views public.
- Correct remaining validation/editor copy to work items and required actions, including singular conversion confirmation.

Final coverage audit adds coordinator tests for bounded revision-conflict retries, cancellation after fetch, cancellation after a completed atomic save, account changes during fetch, and checkpoint retention/filtering across restart and account changes. These exercise coordinator behavior through controlled provider responses. The shared provider suite covers conditional revisions with an in-memory provider; this is not live CloudKit transport verification.

Native inspection:
- iPhone 17 Pro, iOS 26.3: opened the simulator-signed app; verified Outcome, Start review, Convert to outcome, Required actions and Erase current list. Created a disposable action, converted it to an outcome with a required action, and erased that test list through confirmation. The simulator account was signed out.
- macOS: built a temporary host outside the repository using the real UI/Application/Core modules, memory-only storage and a signed-out provider. Verified Focus, All work, sidebar navigation, Outcome, Convert to outcome, Required actions and Settings/Erase current list. Closed the host afterward. This does not test production startup, entitlements, push, or CloudKit.
- Earlier unsigned simulator launch crashed in CKContainer initialization; a simulator-signed build opened successfully. Do not launch the unsigned CloudKit app for UI checks. A native Mac CloudKit launch requires development signing; ad-hoc signing was rejected by Xcode.

Verification commands and results:
- `swift test --disable-sandbox` with writable module caches: 71 tests passed, including two Apple CloudKit format tests.
- `python3 scripts/test_codex_sync_hook.py`: 9 tests passed.
- `python3 scripts/test_contract_checks.py`: 9 negative/checker tests passed.
- `python3 scripts/check-contracts.py`: naming, imports, dependencies, membership, retirement and generated identity passed.
- `python3 scripts/generate-xcode-project.py --check`: generated output current, without writes.
- Unsigned iOS simulator and macOS `xcodebuild` commands from README: both passed.
- `git diff --check` and the unchanged-hook comparison passed.

Linux cannot run locally because no Linux container runtime is installed. CI uses the Swift 6.0 Linux image and runs Swift tests as an ordinary user so root cannot bypass the filesystem permission checks. Its remote result is separate from local verification.

Remaining release verification: register the new identifiers, obtain Apple development/distribution provisioning, deploy the CloudKit schema, and run signed two-device/account-switch/push/recovery scenarios. No result above claims these are complete.

Publication follows repository rules: explicitly stage this task, commit, fetch again, push to `origin/codex/swift`, compare GitHub's branch SHA to local HEAD, and report any remaining local files.

Post-publication CI exposed two environment differences: the Swift Linux image lacks Python, and the hosted Apple compiler rejects nested tasks that implicitly capture a weak variable from a callback. CI now installs Python before checks; the CloudKit callbacks bind a stable actor reference before creating each task. The failing CI compile is the regression evidence for this compatibility fix. Local tests/builds are rerun before publishing the follow-up; hosted CI must then verify the Linux and Apple environments.

Final hosted verification: [GitHub Actions run 38986083867](https://github.com/vsodem/dotlist-plus/actions/runs/38986083867) passed for implementation commit `4fb9159a177e76f61812c047e862d66ae29843d7`: Linux Swift tests, Apple Swift tests, all Python checks, and both unsigned Apple builds. Both implementation commits were pushed and their GitHub SHAs verified. This final record update changes documentation only; the release limitations above still apply.
