# Dotlist app architecture

Status: working specification for the native iPhone/Mac implementation on `codex/swift`; subject to further change and iteration.

This document defines a dot-list app with projects, broad tasks, actionable substeps, and prerequisites. It is written for both the person editing the rules and Codex implementing them. **Change the rules here before changing behavior in code.**

To change a rule without programming: edit the relevant paragraph and its example or acceptance check, then ask Codex to implement that change. Editing this document does not automatically alter the running app. The implementation map is at the end.

## 1. Decisions and scope

### Agreed decisions

- A prerequisite expresses something that must be finished before another action becomes available.
- A broad task can contain smaller actions. Containment does not imply an execution order.
- Review presents available actions with their parent label, rather than presenting the broad parent for selection.
- Completing a prerequisite makes dependent actions available, but they wait for the next review. They do not enter the existing dotted chain.
- Partially working on a prerequisite does not satisfy it.
- The app is native SwiftUI, primarily for iPhone, with a native Mac app sharing the same rules.

### Proposed defaults used by this implementation

These remain revisable defaults, distinct from the agreed decisions above:

- Use the original FV comparison question and reverse-chain execution.
- Require every prerequisite to be complete. No alternative-prerequisite conditions in the first version.
- Treat every child included in a broad task as required. Optional work remains outside that parent's completion requirements.
- Allow one level of broad tasks within a project; defer nested broad tasks and cross-project prerequisites.
- Keep data local. No backend, accounts, or sync.

The supplied architecture referred to a separate “Original Final Version architecture” research report. That report is not present in this repository. Projects and dependency handling are our extension, not rules attributed to Forster. This implementation follows the supplied specification; it does not claim independent verification of that research.

**Native adaptation:** The supplied browser-oriented default is superseded by the earlier choice of native SwiftUI. The original browser demo remains available. Native data is saved in an atomic local JSON file. Browser data is imported through an exported JSON file without changing the old browser storage key. Section 9 describes the adaptation.

## 2. Concepts

| Concept | Meaning | Example |
|---|---|---|
| Project | A named collection of related work | Lunch |
| Broad task | An outcome represented by required child actions | Clean room |
| Action | A specific piece of work that can enter review | Sweep floor |
| Prerequisite | An action that must be complete before another is available | Sweep floor before Mop floor |
| Available | An unfinished action whose prerequisites are complete | Buy groceries, when it has no prerequisites |
| Blocked | An unfinished action with at least one incomplete prerequisite | Cook lunch while groceries remain unbought |
| Dot | Membership in the current selected chain | Selected to be worked during this cycle |

Projects group work. Broad tasks describe what their children collectively accomplish. Prerequisites describe order. Store these relationships separately.

An action can belong directly to a project, to a broad task in that project, or to neither. A broad task can also exist without a project. A prerequisite must point to an action in the same project; two actions without a project can also be linked.

Review labels use the available context: `Lunch › Buy groceries`, `Home › Clean room › Sweep floor`, or simply `Reply to Alex`. Projects and broad tasks never receive dots.

## 3. Rules that must always hold

1. **Only available actions can be dotted or executed.** Urgency does not bypass a prerequisite.
2. **Availability and selection are separate.** Becoming available never automatically adds a dot.
3. **Task identity survives partial work.** Moving an unfinished action to the bottom preserves its ID, parent, project, and prerequisites.
4. **Completion means finished.** Working on an action without finishing it leaves its completion field empty.
5. **Normal completion preserves the remaining chain.** No automatic rescan occurs between dotted actions.
6. **Each review has a fixed candidate list.** Capture available actions when review begins. Newly added or unlocked actions wait for another review, except an explicit urgent action.
7. **The chain determines execution order.** Work from its end toward its beginning; do not sort execution by project or dependency depth.
8. **No circular prerequisites.** Reject a change if following prerequisite links can lead back to the same action.
9. **Resuming and erasing are different operations.** Reloading or starting a new day never clears work or selections.

Rules 3 and 4 are essential: the browser demo finishes an old entry and creates a new one for partial work. That behavior must not be copied into this design, because it would falsely satisfy prerequisites.

## 4. Minimal saved data

Use stable IDs for references. Do not use task titles or array positions as identity.

```text
Project
  id
  title

Task
  id
  title
  kind: action | group
  projectId: ID or null
  parentId: group ID or null
  prerequisiteIds: action IDs[]
  completedAt: timestamp or null

AppState
  schemaVersion: 2
  projects: Project[]
  tasks: Task[]
  actionOrder: action IDs[]
  selection:
    phase: idle | reviewing | executing
    chain: action IDs[]
    candidates: action IDs[]
    cursor: integer
```

`group` means broad task. Groups have no parent, prerequisites, or stored completion timestamp in this version. A child must share its parent's project. Group membership is derived from children's `parentId` values.

`actionOrder` contains each unfinished action exactly once, including blocked actions. Completed actions remain in `tasks` so dependency references keep working. The chain stores dots in selection order; its last ID is the current comparison benchmark or next action. Do not also store `dotted` or `dotOrder` on tasks.

In idle, the chain and candidates are empty and the cursor is zero. In execution, the chain is nonempty, candidates are empty, and the cursor is zero. In review, the cursor identifies the next candidate and the chain contains the selected IDs in order. Neither array may contain duplicate IDs.

Availability is derived, not stored:

```text
available(action) =
  action.kind is action
  AND action.completedAt is null
  AND every prerequisite has completedAt set
```

A nonempty group is complete when all its children are complete. An empty group means “Needs breakdown,” not “Complete.” Project progress is derived from its actions; an empty group also prevents the project from appearing complete. A project with no work is empty, not complete.

Native file details: IDs are strings; completion timestamps are milliseconds since Unix epoch, matching the browser data. Optional fields omitted by Swift's JSON encoder have the same meaning as null. The file directly contains AppState, with no extra envelope.

## 5. Selection and execution

### Begin a review

From idle, capture available actions in `actionOrder` order. If none exist, stay idle and show blocked work or groups needing breakdown. Show “No remaining work” only when neither remains. Never dot a blocked action to force progress.

Otherwise, set `candidates` to that snapshot, dot its first action by putting its ID in `chain`, and set `cursor = 1`. If there is only one candidate, enter execution immediately.

For each later candidate, ask: **“Do I want to do [candidate] before [last dotted action]?”** Yes appends its ID to the chain. No leaves the chain unchanged. Both advance the cursor. At the end, enter execution and clear the candidate snapshot and cursor.

### Complete an action

Finish only the last action in the chain. Set its completion timestamp, remove its ID from `actionOrder`, and remove its dot. Recalculate availability and group progress.

If dots remain, continue executing them. Newly available actions remain undotted. If no dots remain, enter idle and offer the next review. Do not silently start selecting a new chain.

### Work without finishing

Remove the last dot, leave the action incomplete, and move its existing ID to the bottom of `actionOrder`. Preserve all relationships. Continue the remaining chain, or return to idle if it is empty. No dependent action is unlocked.

### Other changes during a cycle

New ordinary actions are appended undotted and wait for the next review. Titles may be edited at any time.

Changes to prerequisites, existing parent membership, deletion, and reopening completed work require returning to idle through the explicit “Choose again” operation. Do not silently discard a selection when editing a title or adding ordinary work.

The first implementation does not offer out-of-order completion during a review or execution cycle. The old demo shortcut would need separate rules before being retained.

Native implementation defaults: new ordinary actions may be assigned to an existing project or broad task at creation; adding prerequisites or creating a broad task requires idle. Creating or deleting projects also requires idle, while renaming projects is allowed at any time. Moving a broad task between projects moves its children with it and rejects the entire change if it would create cross-project prerequisites.

### Break an existing action into substeps

While idle, an unfinished action without a parent can become a broad task with one or more required child actions. Keep the original ID for the group; give each child a new ID and the same project. Replace the old action's position in `actionOrder` with the children in the user's chosen order. This list order does not itself create prerequisites. Breaking down an existing child would require nested groups, which are outside this version.

Transfer the original prerequisites to every child. For each action that depended on the original, replace that link with links to all the children. Clear the group's prerequisite list. Validate and save the whole change together. Show these transferred relationships before applying the breakdown. These are explicit action links: adding a child later changes group progress but does not silently add prerequisites to other actions.

## 6. Urgent work and restarting

**Urgent available action:** append or move its ID to the bottom of `actionOrder`, remove any existing occurrence from the chain, then append it once to the chain. It becomes next-up. From idle, enter execution. During execution, preserve the other dots.

If urgent insertion happens during review, end that review, retain the dots already selected, and execute the urgent action first. Discard the remaining candidate snapshot. Unreviewed actions wait for the next review. This remains a proposed app rule to avoid changing the benchmark while retaining a misleading cursor.

The app tracks a next action, not a timed work session. Urgent insertion changes next-up immediately; it cannot determine whether the person has physically stopped working.

**Urgent blocked action:** follow its prerequisite links to show available prerequisite actions, and let the user explicitly choose one to make urgent. Do not dot the blocked action or choose a prerequisite automatically. Completing that prerequisite still leaves the dependent action waiting for review. Urgency does not propagate automatically.

| Operation | Effect |
|---|---|
| Resume | Restore the saved phase, dots, candidates, and cursor. |
| Next review | From idle, begin a fresh availability snapshot. |
| Choose again | Clear selection state and return to idle; preserve tasks, relationships, completion, and list order. |
| Erase all data | After explicit confirmation, clear tasks, projects, and selection. |

Keep these controls distinct. A specialized rescan below the remaining dot is outside this first implementation; Choose again always starts fresh. Erase clears the active list; native recovery backups remain on the device, as explained in section 9.

## 7. Worked examples

### Lunch with an existing dotted chain

List order: Reply to Alex, Buy groceries, Cook lunch. Cooking requires groceries. At review start, candidates are Reply to Alex and Buy groceries; cooking is excluded.

Reply to Alex is dotted first. Answer Yes to doing Buy groceries before Reply to Alex. The chain is now Reply to Alex, Buy groceries, so groceries runs first. Finish groceries. Cooking becomes available, but it is not dotted. Reply to Alex remains next. After replying, the chain is empty and the next review includes cooking.

If groceries had been the only dot, the next review would be offered immediately after completing it. Starting groceries without finishing them would leave cooking blocked.

### Cleaning with both containment and order

Clean room contains Organize belongings, Sweep floor, and Mop floor. Only Mop floor requires Sweep floor. Organizing has no prerequisite.

Review can offer Organize belongings and Sweep floor independently, with Clean room in both labels. Finishing sweeping makes mopping available for the next review. Finishing mopping does not complete the group while organizing remains unfinished.

### Partial work preserves the link

Buy groceries has ID `groceries`; Cook lunch depends on `groceries`. After partial work, move `groceries` to the bottom without changing its ID or completion timestamp. Cooking still depends on the same unfinished action. Completing `groceries` later satisfies the link.

## 8. Implementation boundaries

| Responsibility | Owns |
|---|---|
| Task rules | Relationships, validation, availability, derived group progress |
| Selection rules | Review snapshot, dots, Yes/No, completion, partial work, urgent insertion, choosing again |
| List merge | Baseline-relative task fields, relationship units, ordering, review handoff, conflicts |
| Sync coordinator | Serialized changes, validation, account partitions, durable pending uploads and conflict decisions |
| Local storage interface | Async load and atomic transaction save, including recovery copies |
| Remote sync interface | Account/connection availability, snapshots, opaque revisions/checkpoints, conditional publication and sync requests |
| Backup codec | Browser import and version-2 JSON import/export, independent of local storage |
| UI store | Injected dependencies, durable list state, actions, status and conflict choices |

Task and selection functions accept state and an action, and return the next state or a clear validation error. They must not read the interface or storage. Apply each change as one state transition, then save and render it. This makes the rules testable without an Apple device and editable without redesigning the UI.

The native store saves before publishing the changed state. When a write fails, the previous state stays visible with an explanation that the change was not saved. Multiple edits in one form are validated and saved together.

## 9. Validation, storage, and migration

Reject missing references, duplicate prerequisite IDs, self-dependencies, cycles, group prerequisites, invalid parent types, and cross-project links. Deleting a referenced prerequisite must fail with an explanation; let the user explicitly change the relationship first. A nonempty group cannot be deleted until its children are moved or removed.

Reopening an action with completed dependents requires first reopening those dependents. Do not retain an impossible completion order. Reopening is available only while idle and appends the reopened action to `actionOrder`.

Persist the entire state after a successful transition. On reload, validate it before resuming. If task data is valid but selection state is invalid, preserve the tasks, clear selection, and explain that a new review is needed. If task data is invalid, retain the original saved data and show a recovery error; do not replace it with demo tasks. Surface save failures so the user knows changes are not yet durable.

### Browser-to-native migration

1. In the original browser app, Export for native app downloads the saved `dotlist-v1` JSON. It does not modify that key.
2. Import the file using Settings in the native app. Validate it before replacing native data; show a replacement confirmation.
3. Import each entry as a standalone action with its existing ID, title, and completion timestamp. Use existing active list order for `actionOrder`.
4. Do not guess relationships between old completed entries and similarly named unfinished copies.
5. Begin idle with no dots and explain the one-time selection reset. Future version-2 reloads resume normally.

### Local storage and backups

The JSON storage adapter atomically writes `Application Support/DotList/sync-state-v1.json` inside the sandbox. Its transaction contains account-separated lists, the last shared snapshot, pending work, outgoing upload attempts, retained conflict inputs, and provider-scoped opaque checkpoints. The adapter alone owns paths and local encoding. On first load it migrates `state-v2.json`, preserving task IDs and valid review progress, and saves the transaction before returning. The original file remains untouched. An invalid transaction is preserved for recovery rather than silently replaced.

`BackupCodec` imports browser exports and version-2 JSON, and exports version-2 JSON. Local storage changes must not change this format. Before import, erasure, or conflict resolution, save `backup-<ID>.json` beside the local state. These new recovery files contain the complete local transaction, including inactive accounts; they are distinct from portable version-2 exports. To recover one manually, quit the app, preserve the current transaction, and restore the recovery file as `sync-state-v1.json`. Importing a valid portable backup can recover an unreadable transaction after confirmation; its unreadable bytes are retained in a recovery copy.

### Sync and merge

One personal list belongs to each iCloud account. CloudKit stores one complete validated snapshot as a JSON asset. CKSyncEngine handles incoming changes and subscription state. Conditional CloudKit saves publish only coordinator-approved snapshots; the engine never restores queued outgoing writes. CloudKit records, assets, retries, and engine serialization stay inside its adapter. Core rules and merge code have no filesystem, SwiftUI, or CloudKit dependency.

The coordinator serializes mutations across asynchronous saves and network operations. It validates and saves locally before showing success, and persists the merge plus an outgoing attempt before uploading. Failed local saves leave the previous list visible. Offline changes remain usable and pending; foreground activation, connection recovery, remote notifications, and Settings → Sync now request synchronization. CloudKit schedules background delivery; immediate delivery is not guaranteed.

Merge each incoming snapshot against the last shared version. Combine independent task/project IDs and compatible field edits. A task's kind, project, parent, and prerequisites form one relationship unit. Incompatible edits to the same field, deletion versus editing, and incompatible action ordering need explicit choices. Preserve both snapshots until resolution, even if another sync occurs. Resolve compatible changes together, validate the resulting list, and only then save and publish. If relationship combinations are invalid, offer an explicit complete-list choice, warning that changes found only in the other version will be removed. Complete-list choices retain a recovery copy.

Action order is separate from record-array order. Merge baseline-relative order constraints; insert independent additions next to their preceding action. Record-array order follows the shared snapshot to avoid endless uploads after two devices add different records. First sync uses task/project IDs to combine existing lists; incompatible records require choices. An empty installation downloads the shared list.

Preserve valid one-sided dots, phase, candidates, and cursor. Identical review progress is compatible. If both devices advance differently, or the merged tasks invalidate selected/candidate actions, clear dots and show an explanation that a new review is needed. Task changes themselves remain preserved.

An upload can succeed while its acknowledgement or subsequent local save fails. A matching remote snapshot on retry confirms that attempt. If its revision and contents have both changed since the attempt, ask which complete list to retain. Do not guess whether the intervening device saw the attempted upload: guessing can resurrect deleted work. No unbounded remote history is required.

### Accounts, imports, and erasure

The first confirmed account adopts this installation's unbound local list once. A different account gets its own saved partition, initially empty, and never receives another account's list automatically. Signing out opens a separate device-local list. Switching back restores that account's pending edits and conflicts. A temporary account lookup failure keeps the current partition open and pauses sync. Changes made to the separate local list after the first adoption stay local; transferring them to an account requires an explicit export/import.

Editors close when the account changes. A save also checks the list snapshot shown when an editor opened; a downloaded change requires reopening the editor. Focus actions check the displayed state after waiting for any in-flight sync, so Done or a review answer cannot apply to a different task. Queued mutations also carry an account scope and are rejected if it no longer matches. Provider IDs scope account partitions and checkpoints, so swapping providers cannot reinterpret another provider's metadata.

Import replaces the currently visible list after confirmation, keeps recovery bytes, and participates in sync. Erasure clears tasks, projects, dots, and review in that list and syncs the deletion. Confirmations explicitly explain effects on other devices using the same account. Concurrent remote changes still follow merge/conflict rules; import or erasure does not silently discard unseen conflicting edits. Inactive accounts and recovery files are not erased. Hiding completed work changes only the display.

## 10. Acceptance checks

These scenarios are covered by the acceptance, merge, coordinator, and storage tests in `Tests/DotListCoreTests/`. Coordinator tests use in-memory storage and a fake remote without files, Apple services, or an iCloud account. Shared storage contracts also run against the JSON adapter; the remote contract harness checks revision conflicts against an isolated fake provider.

| Scenario | Required result |
|---|---|
| Cook depends on unfinished groceries | Cook is visible as blocked and excluded from review. |
| Groceries completed while dots remain | Cook becomes available; existing chain is unchanged. |
| Groceries completed as last dot | App returns to idle; next review includes Cook. |
| Groceries partially worked | Same ID moves to bottom; Cook remains blocked. |
| Yes, then No during review | Yes preserves earlier dots; No advances past the candidate without adding a dot. |
| Chain is A, C, D | Execution is D, C, A. |
| Broad task has independent children | Available children compete independently; parent receives no dot. |
| Broad task has unfinished or no children | It is not complete. |
| Referenced action is broken into substeps | Its dependents require all new children; original prerequisites apply to each child. |
| New ordinary action during review | It does not enter the saved candidate snapshot. |
| Urgent available action during review | Review ends; urgent action executes before retained dots. |
| Urgent blocked action | No dot is added to it; available prerequisites are shown. |
| Circular prerequisite attempted | Change is rejected without altering saved relationships. |
| Referenced completed action is hidden | Its record still exists and still satisfies prerequisites. |
| Reload during review or execution | Same valid selection resumes; no automatic new anchor appears. |
| Choose again | Only selection state clears; tasks and their order survive. |
| Invalid saved data or failed save | User sees the problem; existing saved data is not erased. |

| Offline edit then restart | Saved list and pending work resume; reconnect publishes once. |
| Independent edits and additions | Compatible fields and all new IDs survive; repeated sync converges. |
| Delete versus edit or conflicting order | Both versions stay saved until explicit resolution. |
| Invalid merged relationships | Publishing stops; validated complete-list choices are offered. |
| One device advances review | Other device resumes its valid dots and cursor. |
| Both devices advance differently | Tasks survive; dots reset with a new-review explanation. |
| Successful upload, lost acknowledgement | Matching remote is recognized; later remote changes require an explicit choice. |
| Local write fails after upload | Restart recovers pending attempt without duplicating the upload. |
| Remote contains invalid relationships | Local list remains unchanged; sync reports the error. |
| Import or erase | Confirmed replacement/deletion reaches the other device, subject to concurrent conflicts. |
| Account switches or becomes unknown | Separate lists remain isolated; unknown status does not switch accounts. |
| Concurrent async edits or stale editor | Saves serialize without lost updates; wrong-account or changed-state mutations fail. |
| Existing local file migration | IDs and valid review survive, original bytes remain, new transaction resumes after restart. |
| Replace storage/provider implementation | Change startup wiring; rules, coordinator, and screens remain unchanged. |

Core tests validate behavior and storage. They do not substitute for the device-level interface checks in the README.

## 11. Editing this specification

For behavioral changes, edit the relevant rule and its acceptance check together. Keep agreed decisions distinct from defaults. Do not let a UI shortcut silently introduce a different selection algorithm.

Implementation is complete only when the rules, interface, migration, and acceptance checks agree. Scheduling, recurring work, shared lists, browser sync, nested groups, automatic prerequisite generation, and alternative prerequisite conditions are outside this specification.

### Where each rule is implemented

| Want to change… | Start in this document | Implementation |
|---|---|---|
| What is available or complete | Sections 2–4 | `Sources/DotListCore/TaskRules.swift` |
| What a review selects | Section 5 | `Sources/DotListCore/SelectionRules.swift` |
| What partial work or urgency means | Sections 5–6 | `Sources/DotListCore/SelectionRules.swift` |
| How relationships can change | Sections 5, 9 | `Sources/DotListCore/TaskRules.swift` |
| Backup, resume, or import | Section 9 | `Sources/DotListCore/BackupCodec.swift` and `Sources/DotListStorage/JSONLocalStorage.swift` |
| Wording and presentation | Examples and relevant rule | `Apple/DotList/` |

A useful request is: “In section 6, change [current rule] to [new rule]. Here is an example of the result I want. Update the app and acceptance checks to match.” No Swift knowledge is needed to describe that change.
