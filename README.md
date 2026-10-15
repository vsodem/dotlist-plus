# Dot List

An iPhone-first, native SwiftUI app for choosing and doing one action at a time, with a native Mac interface. The shared rules implement the supplied Final Version architecture, including projects, broad tasks, prerequisites, fixed review snapshots, and reverse-chain execution.

## Run the native app

Requirements: **Xcode 15 or newer**, iOS 17+, macOS 14+. No third-party app dependencies or project-generation tools are required.

1. Open `Apple/DotList.xcodeproj` in Xcode.
2. Select the **DotList** scheme.
3. Choose an iPhone simulator and press Run. Choose **My Mac** to run the native Mac app.
4. To install on your own iPhone, select your Apple development team under Signing & Capabilities and change `com.example.DotList` to your own unique bundle identifier. Connect the phone and choose it as the run destination.

The first launch starts with an empty list. On iPhone, use the Focus, All work, and Settings tabs. Mac uses a sidebar and a Dot List menu with keyboard shortcuts. The shared app also adapts to iPad.

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

The native app writes one version-2 JSON file after each successful change, inside its sandbox at `Application Support/DotList/state-v2.json`. The Mac location is normally under `~/Library/Containers/<bundle identifier>/Data/Library/Application Support/DotList/`.

- Quit and reopen to resume the exact valid review or chain; starting a new day does not reset anything.
- Save failures are shown. The app keeps the previous state visible so an unsaved action is not mistaken for success.
- Invalid task data is left untouched, and mutations are disabled until recovery. Invalid selection data is cleared with an explanation while preserving valid tasks.
- Settings can export/import JSON backups between devices. **There is no automatic iCloud or other multi-device sync.** Import replaces the local list after confirmation; it does not merge.
- Before import or erasure, the old file is copied to `backup-<ID>.json` in the same directory. These recovery copies stay local. Export first for a copy accessible through Files or Finder.

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
| `Sources/DotListCore/DotListFile.swift` | Atomic JSON persistence, migration, recovery |
| `Apple/DotList/` | SwiftUI screens and the observable persistence adapter |
| `Tests/DotListCoreTests/AcceptanceTests.swift` | Behavioral acceptance checks |

The Xcode app compiles the same core source files directly; the Swift package exposes them for tests without requiring SwiftUI. There are no duplicated algorithms. If Swift files are added or removed, run `python3 scripts/generate-xcode-project.py` to regenerate source membership. This also resets project settings to the script's defaults, so update the script if retaining a custom signing identifier.

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

Current environment verification: core tests and Swift syntax can be checked on Linux. Apple SDK type checking, simulator launches, signing, and device interaction require Xcode on macOS and are not verified by Linux tests.
