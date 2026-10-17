# Dot List Plus architecture

Product behavior is authoritative in [APP_RULES.md](APP_RULES.md). This document defines implementation ownership and enforceable contracts. [naming.md](naming.md) defines vocabulary and historical exceptions.

## Modules and dependencies

One local Swift package, `DotListPlus`, exposes five products. Arrows mean “imports.”

```text
Application → Core
Storage → Application, Core
CloudKit → Application, Core
UI → Application, Core
App entry point → all five products
```

| Module | Owns | Public boundary |
|---|---|---|
| DotListPlusCore | Domain values, work rules, list transitions, merges, neutral envelope coding, generated identity constants | ListState, WorkItem, Project, SelectionState, ListChange, WorkItemRules, ListRules, WorkProgress, ListMerge, FormatEnvelope, ProductIdentity |
| DotListPlusApplication | Coordinator, account partitions, storage/provider protocols, snapshots, portable backup codec | SyncCoordinator, CoordinatorSnapshot, LocalStorage, RemoteSync, LocalStoreState, AccountListState, BackupCodec and exchanged values |
| DotListPlusStorage | JSON files, paths, recovery copies, atomic replacement | JSONLocalStorage |
| DotListPlusCloudKit | CloudKit assets, conditional writes, revisions, checkpoints, retries and incoming events | CloudKitSync; delegate methods required by CloudKit |
| DotListPlusUI | Observable store, screens, editor drafts, shared components, navigation | DotListPlusStore and RootView |

The Xcode app compiles only its entry point and push-notification glue. It links package products, never package source files. Startup injects a coordinator into UI. No service locator, rule engine or plugin framework is used. Core and Application have no UI, Apple provider or filesystem dependency. Storage and CloudKit do not import one another. Apple targets are included by the package on Apple build hosts; Core, Application and Storage tests also run on Linux.

The observable store retains `ObservableObject`, `@Published` and `@StateObject`. iPhone tabs, Mac sidebar, menus, windows and shortcuts remain at the UI/app boundary. Screens use Core queries for labels and availability, but commit only coordinator commands. File-picker code reads and writes user-selected portable backups; it does not know the internal store path.

## Work relationships

IDs are strings unique within their entity collection in one list. Project references use project IDs; outcome and prerequisite references use work-item IDs. Titles and record-array positions are not identity. No relationship crosses a list or account partition. All relationships persist in `ListState`, inside a versioned format envelope.

| Relationship: participants, direction, cardinality | Owner and allowed operations | Preconditions and result | Failure and tests |
|---|---|---|---|
| Action → outcome, zero or one; outcome → required actions, zero or more | WorkItemRules; addWorkItem, updateRelationships, deleteWorkItem, convertActionToOutcome | Referenced outcome exists; same project; outcome cannot itself have an outcome. Membership determines progress, never execution order. | Reject entire transition. AcceptanceTests covers empty outcomes, containment, referenced deletion and conversion. |
| Work item → project, zero or one; project → work items, zero or more | WorkItemRules; addWorkItem, updateRelationships, deleteProject | Project exists. Moving an outcome moves all required actions atomically; resulting prerequisites must remain within the project. | Reject missing references and cross-project links; AcceptanceTests covers moves and rollback. |
| Action → prerequisite actions, zero or more | WorkItemRules; addWorkItem, updateRelationships, conversion, reopenAction, deletion | Unique existing action IDs, same project (including nil), no self-link or cycle. Completed action cannot have an unfinished prerequisite. | Reject entire transition/import/merge publication; AcceptanceTests and MergeTests cover cycles and conversion. |
| List → action order, exactly one entry per unfinished action | ListRules/WorkItemRules; add, completion, partial work, urgency, reopen, conversion | Includes blocked actions. IDs survive partial work. Record-array order remains separate. | Validation rejects duplicate/missing entries. AcceptanceTests covers reverse execution and identity. |
| Selection → dotted actions, ordered unique available actions; selection → fixed review candidates | ListRules; beginReview, answerReview, completeNextAction, recordPartialWork, makeUrgent, clearSelection | Candidate snapshot fixed during review; selected chain is its ordered subsequence. Execution reverses selection order. reviewBenchmark exists only in review, nextAction only in execution. | Invalid selection is rejected on commands/import. Merge may clear invalidated selection with a notice, never repair work relationships. AcceptanceTests and MergeTests enforce this. |

All work constraints run in `WorkItemRules.validate`. Commands, imports, local load and merges invoke the same validation and `ListRules.validateSelection`. No screen owns a second set of work rules. Draft filtering is presentation assistance; the coordinator still validates the complete result.

## Application and adapter relationships

Normal path: **UI command → coordinator → validated transition → atomic local save → published UI snapshot → conditional cloud upload.**

| Participants, direction and cardinality | Owner, operations and preconditions | Result, failure and scope | Persistence and enforcing tests |
|---|---|---|---|
| One UI store → one coordinator | UI sends commands with displayed scope/state; holds drafts only. App events use the same sync/apply entry points. | Coordinator snapshots are durable displayed state. Failed saves leave the previous snapshot visible. | CoordinatorTests: failed save, stale editor, stale selection, serialized actions; UI observation remains unchanged. |
| One coordinator → one LocalStorage | Coordinator is sole commit/account authority. A gate spans awaits for load, apply, replacement, resolution and sync. Cancellation is checked before starting a transaction and before save. | Whole-store save or throw; never acknowledge an unsaved state. A completed atomic save is reflected even if cancellation arrives afterward. | LocalStoreState retains every account, baseline, outbox attempt, conflict inputs and provider checkpoint. Shared storage suite runs in memory and against JSON. |
| One coordinator → one RemoteSync | Fetch current account and revision; validate and save merge/outbox before publish. Publish is conditional: nil means create only if absent. | Network failure retains pending local work. Revision conflict retries a fresh fetch up to three attempts. Account changes reject in-flight responses. | CoordinatorTests: restart, retries, lost acknowledgement, two-device convergence, signed-out partitions and invalid remote state. Shared provider tests check conditional revisions; coordinator tests check account changes during fetch, bounded retries and checkpoint isolation across restart. |
| Local store → account partitions, zero or more plus a separate local partition | Coordinator selects providerID + account identity. First account adopts local work once; later accounts stay separate. | Signed out opens local partition; temporarily unavailable account preserves current partition. | All partitions validated and saved together. CoordinatorTests and StorageTests cover inactive partitions and restart. |
| Cloud events → coordinator sync requests, many to one | Provider emits requests; UI observation routes them to syncNow. | Events never publish state independently. Restored CKSyncEngine outgoing record/zone queues are discarded. | CloudKit owns opaque, account-scoped revision/checkpoint coding; signed-device release checks exercise Apple transport. |
| Storage → filesystem | JSONLocalStorage owns directory and atomic sibling-file replacement. | Existing incompatible file blocks ordinary writes. Write/flush failure leaves old bytes readable. | StorageTests covers permissions, failed writes, unchanged old files, localStore recovery copies and restart. |
| Portable backup → one list | Application BackupCodec validates envelope and relationships before coordinator replacement. | No account/provider metadata; localStore recovery copies are rejected by portable import. | FormatContractTests and AcceptanceTests. Recovery restoration is a separate offline operation with the app closed. |

## Merge conflict policy

A valid local list and valid remote list can combine into an invalid relationship graph. Core returns no publishable state and the `list.structure` conflict; it never invents links or removes cycle edges. Application retains the complete base, local and remote inputs. The interface explains that choosing one complete list removes changes unique to the other. Resolution validates the chosen list, preserves a complete localStore recovery copy, and saves it pending publication against the retained remote revision. Sync fetches again before publication; newer remote changes may create another conflict. CoordinatorTests exercises a merge-created cycle, fixed conflict inputs, restart, explicit resolution and convergence.

An interrupted upload with an unknown result retains its attempted state/revision. A matching fetched state acknowledges it. A different remote revision requires complete-list resolution rather than guessing whether deletions should be recreated.

## Identity and persisted formats

`product-identity.json` is the generator input. `scripts/generate-xcode-project.py` generates runtime constants, entitlements, Xcode source membership and package links. `--check` compares every generated byte without writing or creating directories.

Each persisted list-bearing format is `{productID, format, formatVersion, payload}`. Product ID is `com.vsodem.DotListPlus`; formats are `backup`, `localStore`, `cloudSnapshot`, each version 1. Header validation precedes payload decoding. `ListState` has no serialization version. CloudKit revision/checkpoint bytes are provider-private metadata nested inside the localStore payload, not portable formats.

Only absence of the new file starts empty. Old directories, backups and cloud containers are never discovered or migrated. Incompatible new-store bytes block writes; incompatible cloud bytes block uploads. Recovery copies retain the original localStore envelope and all accounts. Future relationship/format changes require explicit version handling and migration tests; unsupported versions never silently fall back.

## Extension rules and checks

- New storage or provider: implement Application's existing contract, pass its shared contract suite and change startup wiring. Keep domain rules/screens unchanged.
- New command: extend ListChange, its owning rules/coordinator behavior and acceptance tests.
- New screen/platform: use commands/snapshots; keep platform behavior outside Core.
- New persisted relationship: change APP_RULES, validation, merge policy, format version and migration tests together.
- New dependency: update this graph and `scripts/check-contracts.py` explicitly.

CI checks target declarations, imports, forbidden filesystem/UI APIs, source membership, names/paths and generated output, including new files. Negative checker tests introduce forbidden imports/dependencies, stale generated files and old names. Swift behavioral/storage/provider tests run on Linux and macOS; CI builds unsigned iOS simulator and macOS apps. Identifier registration, provisioning, CloudKit schema deployment and signed two-device verification remain release requirements, separate from code/build verification.
