# Dot List Plus

A native iPhone and Mac app for choosing and doing one action at a time. Projects organize work; outcomes contain required actions; prerequisites control availability. Review a fixed set of available actions, then work your dotted chain in reverse.

## Run

Open `Apple/DotListPlus.xcodeproj`, select **DotListPlus**, choose an iPhone simulator or **My Mac**, and Run. Requires Xcode 15+, iOS 17+ or macOS 14+. One local Swift package supplies shared behavior and native screens; no third-party app dependencies are required.

- **All work → +:** add an action or outcome. Edit work to choose its project, outcome and prerequisites.
- **Focus → Start review:** Yes adds a dot; No advances. Done completes the next dotted action. Worked on it, not finished retains its ID and moves it to the bottom.
- **Make urgent:** choose an available action; for blocked work choose an available prerequisite explicitly.
- **Choose again:** clear selection only, before changing relationships, deleting or reopening work.
- **Convert to outcome:** preview transferred prerequisites and enter required actions before confirming.
- **Settings:** sync status, explicit conflict choices, portable backups and Erase current list.

Mac shortcuts remain Shift-Command-R/Y/N for review/Yes/No, Command-Return for completion and Shift-Command-P for partial work.

## Rules and code

[THEMES.md](docs/THEMES.md) explains developer theme selection and editing. All app-owned design values and reusable styles live in `Sources/DotListPlusUI/DesignSystem/`. Default follows Apple appearance; TRON adds dark surfaces, cyan glow and brief interaction animations.

[APP_RULES.md](docs/APP_RULES.md) is the editable behavior specification. [architecture.md](docs/architecture.md) defines module ownership, relationships and extension contracts. [naming.md](docs/naming.md) records definitions, renames and historical exceptions.

| Location | Ownership |
|---|---|
| Sources/DotListPlusCore | Domain, transitions, merges and neutral envelopes |
| Sources/DotListPlusApplication | Coordinator, account state, contracts, portable backups |
| Sources/DotListPlusStorage | Atomic local JSON and recovery copies |
| Sources/DotListPlusCloudKit | CloudKit implementation and provider metadata |
| Sources/DotListPlusUI | Observable store, screens and drafts |
| Apple/DotListPlus | Startup wiring, lifecycle and push notifications |
| product-identity.json | Canonical identity input for generated constants, project and entitlements |

Run `python3 scripts/generate-xcode-project.py` after changing app source membership or identity. `--check` verifies generated output without writing. Xcode links package products rather than compiling package source files directly.

## Data and sync

This identity starts fresh: bundle `com.vsodem.DotListPlus`, container `iCloud.com.vsodem.DotListPlus`, zone `DotListPlus`. The new local file is `Application Support/DotListPlus/local-store-v1.json` within the app sandbox. Old app directories, backups and cloud containers are left untouched and are not imported or migrated.

Every persisted list format validates product identity, format kind and version 1 before decoding its payload. Missing or incompatible metadata blocks replacement. Only an absent new local file starts empty. Additional devices can download existing Dot List Plus cloud data.

Portable exports use `dot-list-plus-backup.json` and contain one list. Recovery copies use `dot-list-plus-recovery-<ID>.json` beside the local store and retain all account partitions and sync information. Restore recovery copies separately with the app closed; preserve the current file and validate the recovery copy before replacing the local-store file. Portable import rejects recovery files.

Edits save locally before upload. Save failure preserves the visible state; network failure keeps work pending. Accounts remain separate. Independent edits merge; incompatible changes retain both versions until explicit resolution. Choosing a complete version removes changes unique to the other, with a recovery copy retained. Invalid relationships are never silently repaired.

The browser demo and browser integration are retired. Historical research and plans retain source terminology and pinned links; they are not current-use instructions.

## Verify

```sh
swift test
python3 scripts/test_codex_sync_hook.py
python3 scripts/check-contracts.py
python3 scripts/test_contract_checks.py
python3 scripts/generate-xcode-project.py --check
xcodebuild -project Apple/DotListPlus.xcodeproj -scheme DotListPlus \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/DotListPlus-iOS CODE_SIGNING_ALLOWED=NO build
xcodebuild -project Apple/DotListPlus.xcodeproj -scheme DotListPlus \
  -destination 'platform=macOS' \
  -derivedDataPath /tmp/DotListPlus-Mac CODE_SIGNING_ALLOWED=NO build
```

CI runs Linux/macOS tests, naming/dependency/generated checks, hook tests and unsigned Apple builds. In restricted environments, place Swift's module cache in a writable directory and use `swift test --disable-sandbox`; Xcode also needs access to its caches and Simulator services.

## Release requirements

Unsigned builds do not verify Apple services. Before release:

1. Register the new bundle/container with team `NYZA33Z8N5`, enable iCloud and Push Notifications, and obtain signing identities/profiles.
2. Create the private `DotListPlus` zone and `ListSnapshot` schema (`listJSON` Asset, `formatVersion` Int64, `account` String). Deploy the schema to Production; Debug uses Development and Release uses Production.
3. Install signed builds on two devices. Check fresh-device download, offline edits/reconnect, independent and conflicting changes, conditional writes, merge-created cycles, review handoff and interrupted-upload restart.
4. Check account switching/sign-out with pending edits/conflicts, push/background updates, portable replacement/erasure and recovery. Verify neither account receives another account's work.
5. Inspect VoiceOver, Dynamic Type, keyboard shortcuts, dark mode, landscape and Mac window resizing.

Identifier registration, provisioning, schema deployment and signed two-device verification remain separate release checks.
