# Dot List

An iPhone-first, native SwiftUI app for choosing and doing one action at a time, with a native Mac interface. The shared rules implement the supplied Final Version architecture, including projects, broad tasks, prerequisites, fixed review snapshots, and reverse-chain execution.

## Run the native app

Requirements: **Xcode 15 or newer**, iOS 17+, macOS 14+. No third-party app dependencies or project-generation tools are required.

1. Open `Apple/DotList.xcodeproj` in Xcode.
2. Select the **DotList** scheme.
3. Choose an iPhone simulator and press Run. Choose **My Mac** to run the native Mac app.
4. To install on your own iPhone, use the configured team `NYZA33Z8N5` and register `com.vsodem.DotList` with the `iCloud.com.vsodem.DotList` CloudKit container under Signing & Capabilities. A valid development certificate and provisioning profiles with iCloud and Push Notifications are required. Connect the phone and choose it as the run destination.

On first launch, an existing iCloud list downloads when available; a new account starts empty. On iPhone, use the Focus, All work, and Settings tabs. Mac uses a sidebar and a Dot List menu with keyboard shortcuts. The shared app also adapts to iPad.

## Use it

- **All work → +:** add an action or broad task. Use the folder button to create projects. Edit an action to select its broad task and the actions that must finish first.
- **Focus → Next review:** compare available actions. Yes adds a dot; No advances. Work the dots in reverse order.
- **Done:** finish the next dotted action. Newly unlocked actions wait for the next review.
- **Worked on it, not finished:** move the same unfinished action to the bottom. It retains its relationships and does not unlock dependents.
- **An action's menu → Make urgent:** put an available action next. For a blocked action, choose an available prerequisite explicitly.
- **Choose again:** clear only the dots and review. Use this before editing relationships, deleting work, or reopening completed actions.
- **Edit work → Break into substeps:** enter one required substep per line. Review the transferred relationships before confirming.
- **Show completed actions:** reveal completed records. Hiding them never removes prerequisite records.

Mac shortcuts: Shift-Command-R starts review, Shift-Command-Y answers Yes, Shift-Command-N answers No, Command-Return completes the next action, and Shift-Command-P records partial work. Shortcuts are enabled only in the appropriate phase.

## Change the rules without knowing Swift

Start with **[the editable app specification](docs/APP_RULES.md)**. It distinguishes agreed decisions, proposed defaults, and native storage adaptations.

Edit the rule and its example or acceptance check together, then ask Codex to implement it. For example: “Change section 6 so that [desired behavior]. With actions A, B, C, I expect [result]. Update the tests too.” Editing the document alone does not change the running app.

Settings → How Dot List works includes a plain-language guide and a bundled copy of the full specification. Rebuild the app to include changes to that document.

## Saving, backups, and browser migration

The native app atomically saves its list and durable sync state after each successful change in `Application Support/DotList/sync-state-v1.json`. It migrates the previous `state-v2.json` in the same sandbox once, preserving its IDs and valid review progress and retaining the original file. The Mac location is normally under `~/Library/Containers/<bundle identifier>/Data/Library/Application Support/DotList/`.

- Quit and reopen to resume the exact valid review or chain; starting a new day does not reset anything.
- Save failures are shown. The app keeps the previous state visible so an unsaved action is not mistaken for success.
- Invalid task data is left untouched, and mutations are disabled until recovery. Invalid selection data is cleared with an explanation while preserving valid tasks.
- iCloud sync combines tasks, projects, order, dots, and valid review progress across Apple devices using the same account. Offline edits save locally and upload when connectivity returns. Settings shows status, conflicts, and **Sync now**.
- Settings still exports/imports version-2 JSON and browser exports. Import and erasure affect the synced list after confirmation; concurrent changes may require conflict choices.
- Before import or erasure, the old file is copied to `backup-<ID>.json` in the same directory. These recovery copies stay local and contain the full storage transaction, including account partitions. They are separate from portable version-2 exports. To restore a recovery copy, quit the app, preserve the current file, and replace `sync-state-v1.json` with the recovery copy. Export first for a portable copy accessible through Files or Finder.

The first signed-in account adopts the existing local list once. Later accounts keep separate lists. Signing out opens a separate local list; signing back in restores that account's pending work. Temporary account lookup failures pause sync without switching lists. Local work created after signing out can be transferred explicitly by export/import.

Independent edits merge automatically. Conflicting edits, deletion versus editing, or incompatible order require choices in Settings. Both versions remain saved until resolution. One-sided valid review progress continues on the other device; conflicting or invalidated progress resets with an explanation. If an upload's acknowledgement is lost and another device changes the list before retry, choose which version to keep; the app will not guess and resurrect deleted work.

If upgrading an installation that used the old `com.example.DotList` bundle identifier, export a backup before switching identifiers: Apple gives the new identifier a different sandbox. Import that backup in the new app. In-place storage migration applies within the same sandbox.

For existing browser users:

1. Open the updated `index.html` **at the same origin/browser profile as your existing list**. Browser storage is tied to its origin; a different URL will not see the original data.
2. Click **Export for native app** in the footer. This downloads the original `dotlist-v1` JSON without changing browser storage.
3. In the native app, choose Settings → Import backup or browser list, then select that JSON file and confirm replacement.
4. Tasks keep their original IDs, text, dates, and active order. Migration clears the old dots once and starts idle. It does not infer relationships between similarly named entries.

The old web demo still works by opening `index.html` or running `python3 -m http.server`. Its original task algorithm is unchanged; only a JSON export control was added. The project/prerequisite model is implemented in the native app.

## Code map

| Location | Responsibility |
|---|---|
| `docs/APP_RULES.md` | Editable behavior specification and examples |
| `Sources/DotListCore/AppState.swift` | Version-2 data and explicit operations |
| `Sources/DotListCore/TaskRules.swift` | Relationships, validation, progress, breakdown |
| `Sources/DotListCore/SelectionRules.swift` | Pure validated state transitions |
| `Sources/DotListCore/BackupCodec.swift` | Independent browser/version-2 backup format |
| `Sources/DotListCore/SyncInterfaces.swift` | Async storage/remote contracts and durable transactions |
| `Sources/DotListCore/ListMerge.swift` | Pure three-way merge and conflict choices |
| `Sources/DotListCore/SyncCoordinator.swift` | Serialized saves, merge/retry/account decisions |
| `Sources/DotListStorage/JSONLocalStorage.swift` | Atomic JSON files, migration, recovery |
| `Apple/DotList/CloudKitSync.swift` | Private CloudKit record/asset format, CKSyncEngine, retries |
| `Apple/DotList/` | SwiftUI screens, injected observable store, and startup wiring |
| `Tests/DotListCoreTests/AcceptanceTests.swift` | Behavioral acceptance checks |

The Xcode app compiles the same core and storage source files directly; the Swift package exposes them for tests without requiring SwiftUI. There are no duplicated algorithms. If Swift files are added or removed, run `python3 scripts/generate-xcode-project.py` to regenerate source membership. The generator preserves the configured Apple team, identifiers, CloudKit and push entitlements, and iOS remote-notification background mode. Update the generator when changing those settings.

To replace local storage, implement `LocalStorage` and change `DotListApp.init` wiring. To replace remote sync, implement `RemoteSync` and change that wiring and its display name. The coordinator sees only snapshots, strings, and opaque provider-scoped checkpoints. No rules or screens need provider-specific edits. CKSyncEngine handles incoming changes; explicit conditional CloudKit writes publish the one `ListSnapshot` record containing a `listJSON` asset. No restored engine outgoing queue can publish old data. Backups do not serialize provider metadata.

## Verification

Run the shared behavior and persistence tests on macOS or Linux with Swift 5.9+:

```sh
swift test
```

Build both native targets on a Mac:

```sh
xcodebuild -project Apple/DotList.xcodeproj -scheme DotList \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/DotList-iOS CODE_SIGNING_ALLOWED=NO build

xcodebuild -project Apple/DotList.xcodeproj -scheme DotList \
  -destination 'platform=macOS' \
  -derivedDataPath /tmp/DotList-Mac CODE_SIGNING_ALLOWED=NO build
```

The GitHub Actions workflow runs the core tests plus both Apple builds when pushed. Adding the workflow does not mean those Apple builds have already run.

Before treating a release as device-verified, check on both an iPhone simulator/device and Mac:

1. Add a project, a broad task, independent children, and a prerequisite. Confirm labels and blocked reasons.
2. Run the Lunch example in the specification. Confirm cooking waits for the next review.
3. During a review add ordinary work, rename a task, and quit/relaunch. Confirm the candidate and existing dots resume exactly.
4. Mark partial work and make blocked work urgent through an explicit prerequisite choice.
5. Preview a breakdown and verify transferred prerequisites before confirming.
6. Export, change the list, import the backup, and confirm restoration. Test a malformed JSON import without losing the existing list.
7. Check large Dynamic Type, VoiceOver labels, dark mode, landscape, keyboard shortcuts, and Mac window resizing.
8. Confirm Choose again preserves work and Erase all data requires confirmation.

### iCloud release verification

Code verification on October 15, 2026: 60 core/storage/coordinator tests pass, and unsigned macOS and iOS simulator builds pass. **Live two-device sync is not verified.** The machine has zero valid signing identities; the signed iPhone build fails because no development profile exists for `com.vsodem.DotList`. Container/identifier registration and development/production schema availability remain unverified.

With signing available:

1. Register/associate the identifiers above with the configured team. Enable iCloud/CloudKit and Push Notifications, generate development profiles, and install signed builds on two devices signed into the same iCloud account.
2. Use development builds to create the private `DotList` zone and `ListSnapshot` schema (`listJSON` Asset, `formatVersion` Int64, `account` String). Deploy the schema to Production in CloudKit Console before distributing Release builds; Debug uses Development and Release uses Production.
3. Confirm an empty device downloads the list. Add different tasks offline on both, reconnect, and confirm convergence with no repeated uploads. Try independent field edits, conflicting titles, delete/edit, and differing order.
4. Hand off a review and execution chain; advance differently offline on both and confirm reset notice. Restart during a pending upload and retry after a connection failure.
5. Import and erase with confirmations and confirm propagation. Switch accounts and sign out/back in, including with pending edits and unresolved conflicts; confirm neither account receives the other's list.
6. Check foreground and background incoming changes, Sync now, airplane mode recovery, unavailable/restricted account status, and a full-disk save failure.

The shared remote contract in `CoordinatorTests` verifies compare-and-swap behavior against a fake provider. CloudKit's actual subscriptions, asset transfer, server revision conflicts, signing, and account-switch races require these signed-device checks; local tests do not establish them.
