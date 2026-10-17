# Dot List Plus product rules

This is the authoritative, editable behavior specification. Change a rule and its acceptance check together, then update code. Editing this document alone does not change the app. Implementation ownership and dependency contracts live in [architecture.md](architecture.md); definitions and old-to-new mappings live in [naming.md](naming.md).

## 1. Decisions and scope

The product is **Dot List Plus**. Use **Project / Outcome / Action**. iOS and macOS share rules, storage/sync contracts and screens where appropriate, with native navigation, windows, menus and shortcuts. Preserve native behavior except for the explicit fresh identity, strict formats, naming and boundaries described here. The browser demo is retired.

Containment describes a result; prerequisites describe execution constraints. Neither a project nor an outcome receives dots. No nested outcomes, cross-project prerequisites, alternative prerequisites, automatic prerequisite generation, recurring work or shared-account collaboration is supported.

## 2. Work and relationships

A project is a named collection of related work. A work item is an action or outcome. An action is work that can receive a dot and be performed. An outcome is a result completed through its required actions.

- An action belongs to zero or one outcome and zero or one project.
- An outcome belongs to zero or one project and contains zero or more required actions. Every required action shares its outcome's project.
- An outcome has no containing outcome, prerequisite links or stored completion date.
- A prerequisite connects actions in the same project. Two actions without a project may connect.
- Reject missing references, duplicate IDs, duplicate prerequisite links, self-links and cycles. A completed action cannot depend on an unfinished prerequisite.
- An action is available exactly when it is unfinished and every prerequisite is complete.
- A nonempty outcome is complete only when all required actions are complete. An empty outcome is incomplete and displays “Needs required actions.”
- Project progress is derived from its actions. Any empty outcome prevents completion. A project without work is empty, not complete.

Labels use available context: `Lunch › Buy groceries`, `Home › Clean room › Sweep floor`, or `Reply to Alex`.

## 3. State and invariants

IDs survive renames, partial work and moves. Completion timestamps are finite, nonnegative milliseconds since Unix epoch. Titles and IDs must be nonempty. Array positions and titles are never identity.

`ListState` contains projects, workItems, actionOrder and selection. Each work item has id, title, kind (action/outcome), projectID, outcomeID, prerequisiteIDs and completedAt. SelectionState contains phase, dottedActionIDs, candidateActionIDs and candidateIndex. Format versions belong outside ListState.

Three orders remain distinct:

1. Record-array order stores work-item records; merge uses a stable shared order for convergence.
2. Action order contains each unfinished action exactly once, including blocked actions.
3. Dotted-chain order records selection order and is executed in reverse.

Only available actions enter review or the dotted chain. In idle, the dotted chain/candidates are empty and candidateIndex is zero. In executing, the chain is nonempty, candidates are empty and index is zero. In reviewing, candidates are fixed and the chain is an ordered subsequence of the reviewed prefix, beginning with the first candidate. IDs cannot repeat. `reviewBenchmark` is the last dot during review; `nextAction` is the last dot during execution.

## 4. Review

**Start review** (`beginReview`) requires idle. Capture the available actions in action order. If none exist, remain idle and show blocked work or outcomes needing required actions; show “No remaining work” only when neither exists.

Dot the first candidate automatically. For each later candidate ask: **“Do I want to do [candidate] before [last dotted action]?”** `answerReview(true)` adds a dot; false leaves the chain unchanged. Both advance to the next candidate. When candidates are exhausted, enter execution and clear candidates/index. One candidate enters execution immediately.

The candidate set remains fixed. Ordinary new or newly unlocked actions wait for another review. Urgency is the explicit exception described below.

## 5. Execute and edit

`completeNextAction` finishes only the last dotted action during execution, removes it from action order and removes its dot. Remaining dots continue in reverse order. Newly available dependents remain undotted. When the final dot is removed, enter idle and offer Start review; never begin another review automatically.

`recordPartialWork` removes the last dot, keeps the same action incomplete and moves its ID to the bottom of action order. Relationships stay intact; dependents remain blocked. Continue remaining dots or enter idle.

`addWorkItem` appends an ordinary new action undotted. Titles can change during a cycle through `renameWorkItem` and `renameProject`. Creating outcomes or adding prerequisites requires idle. New ordinary actions may join an existing project/outcome during a cycle without changing review candidates.

`updateRelationships`, `deleteWorkItem`, `reopenAction`, `convertActionToOutcome`, creating/deleting projects require idle. Use Choose again (`clearSelection`) first. Moving an outcome moves all required actions with it; reject the whole change if any prerequisite would cross projects. Deleting a referenced prerequisite or a nonempty outcome fails. A project must have no work before deletion. Reopen completed dependents before reopening their prerequisite. Reopening appends the action to action order.

**Convert to outcome:** while idle, an unfinished action without an outcome may become an outcome with one or more required actions. Retain its ID; create new IDs for required actions, in its project. Replace its action-order position with the required actions in entered order. Transfer its prerequisites to every new action. Replace every dependent's link to the original action with links to all new actions; remove duplicate links. Clear the outcome's prerequisites. Show the transfer before confirmation and validate/save everything atomically. Adding required actions later changes outcome progress but does not silently add links to its dependents.

## 6. Urgency, resume and erasure

`makeUrgent` requires an available action. Move its ID to the bottom of action order and to the end of the dotted chain, with no duplicates. It executes next. From idle enter executing. During execution retain the other dots. During review end review, discard unreviewed candidates and retain selected dots before adding the urgent action.

A blocked action cannot become urgent. Show available prerequisites reached through its prerequisite links; the person explicitly chooses one. Never choose automatically. Finishing that prerequisite leaves the dependent waiting for a later review. Urgency changes next-up; the app does not track whether someone has physically stopped other work.

| Operation | Effect |
|---|---|
| Resume | Restore valid phase, dots, candidates and position. A new day never resets work. |
| Start review | Capture a new fixed set while idle. |
| Choose again | clearSelection clears selection only; preserves work, relationships, completion and action order. |
| Erase current list | eraseCurrentList, after explicit confirmation, clears the active list; retains other account partitions and a recovery copy. Erasure syncs. |

## 7. Examples

**Lunch:** action order is Reply to Alex, Buy groceries, Cook lunch. Cooking requires groceries. Review includes Reply and Buy. Answer Yes to Buy before Reply; chain is Reply, Buy, so Buy executes first. Completing Buy unlocks Cook but leaves Reply next. Only the next review includes Cook. Partial work on Buy keeps Cook blocked.

**Cleaning:** Clean room contains Organize belongings, Sweep floor and Mop floor. Only Mop requires Sweep. Organize and Sweep compete independently. Finishing Sweep unlocks Mop for a later review. The outcome remains incomplete until all three finish.

**Reverse execution:** selected chain A, C, D executes D, C, A. Project grouping, prerequisites and record-array order never reorder that chain.

## 8. Transactions and sync

The coordinator alone commits changes and chooses the active account partition. Screens hold drafts and submit commands with their displayed account scope and expected state. Transactions serialize across asynchronous work. A stale command fails rather than editing a different list/action. Cancellation before a transaction/save prevents commit; an already completed atomic save remains durable and visible.

Normal changes validate, save atomically, update the visible snapshot, then request cloud upload. Save failure preserves the previous visible state. Network failure leaves locally saved work pending. Cloud events request synchronization; they cannot independently publish restored old state.

The first signed-in account adopts the local list once. Later accounts have separate partitions. Signing out opens a separate local list; signing back in restores that account's pending work. Temporary account lookup failure pauses sync without switching lists. Account and provider scope apply to revisions/checkpoints. Backups can explicitly transfer work between lists.

Independent edits merge automatically. Conflicting fields, deletion/edit and incompatible order require explicit choices. Preserve both versions until resolution. Valid one-sided review progress continues; conflicting or invalidated selection resets with an explanation. Work relationships never receive a silent repair.

Separate valid edits can create invalid relationships when merged, such as A requiring B on one device and B requiring A on the other. Reject publication; retain both inputs; offer complete-list choices. Explain that the selected version removes changes unique to the other. Preserve a recovery copy, validate the chosen result, and publish conditionally against the remote revision. New remote edits can require another resolution. Never invent relationships or repair a cycle.

Persist outgoing attempts before upload. If acknowledgement is lost, a matching fetched state acknowledges the attempt. If the remote revision changed to a different state, require explicit resolution instead of guessing whether deleted work should return.

## 9. Identity, formats and recovery

| Purpose | Value |
|---|---|
| Bundle/product ID | com.vsodem.DotListPlus |
| Cloud container | iCloud.com.vsodem.DotListPlus |
| Provider | cloudkit.iCloud.com.vsodem.DotListPlus.private.v1 |
| Cloud zone | DotListPlus |
| Local file | Application Support/DotListPlus/local-store-v1.json |
| Portable export | dot-list-plus-backup.json |

Every persisted list-bearing format has `productID`, `format`, `formatVersion`, `payload`. The three distinct formats are `backup`, `localStore`, `cloudSnapshot`, initially version 1. Validate identity, kind and version before decoding/replacing a payload. All lists and relationships are then validated, including inactive accounts and retained conflict/outgoing states.

Start fresh under these identifiers. Never discover, migrate, import or modify old application data, backups or containers. Only an absent new store starts empty. An incompatible existing store blocks ordinary writes, including portable replacement; an incompatible cloud snapshot blocks uploads. Unsupported/missing metadata never silently falls back. New backups remain importable and subsequent launches preserve new data. Additional devices can download existing Dot List Plus cloud data.

Portable backups contain one list without account/provider metadata. Before import, erasure or conflict resolution, preserve the complete previous localStore as `dot-list-plus-recovery-<ID>.json`. Recovery copies retain localStore format and are rejected by portable import. Restore separately with the app closed: retain the current file, validate the recovery file, and replace the local-store file with that complete copy. UI file pickers access user-selected portable files only. Future format changes require explicit version handling and tested migrations.

## 10. Appearance

Themes change presentation only. Developer-editable visual values and shared styles live in `Sources/DotListPlusUI/DesignSystem`; [THEMES.md](THEMES.md) documents selection and extension. Default ships with native Apple controls, semantic colors, system typography and light/dark appearance. TRON uses dark surfaces, cyan illuminated edges/dots, amber next-action accents and brief interaction animations inspired by TRON: Legacy.

The developer default applies unless the `DOTLIST_THEME` launch environment selects a known theme. Unknown values keep the developer default. No theme preference is stored or synced, and there is no user theme editor. Navigation, editors and secondary screens inherit the same theme. Native system dialogs retain platform styling.

Text remains readable without glow. Reduce Motion disables decorative transitions and press scaling; Increased Contrast removes glow. State labels and symbols remain present, and custom action buttons retain at least a 44-point target. Themes never change work rules, shortcuts, persistence or sync.

## 11. Acceptance checks

| Scenario | Required result / enforcing suite |
|---|---|
| Empty outcome, independent required actions, invalid containment | Derived incomplete progress; reject nesting or mixed projects. AcceptanceTests. |
| Prerequisite incomplete, completed, partially worked, reopened | Availability, blocked reasons and identity follow sections 2–5. AcceptanceTests. |
| Cycle, missing reference, duplicate prerequisite, project move | Atomic rejection; previous list retained. AcceptanceTests. |
| Convert referenced action | Same outcome ID, new required-action IDs, transferred explicit links and action-order position. AcceptanceTests. |
| Yes/No review; chain A,C,D; new work during review | Fixed candidates and execution D,C,A. AcceptanceTests. |
| Urgent available/blocked work; Choose again | Section 6 behavior; no automatic prerequisite choice. AcceptanceTests. |
| Save failure or cancelled/stale command | No unsaved visible state or wrong-account commit; cancellation after atomic save still exposes durable state. CoordinatorTests. |
| Retry, lost acknowledgement, restart, two accounts | At most three revision attempts per sync; durable pending work, account changes during fetch rejected, checkpoints isolated by provider/account. CoordinatorTests and shared provider contract. |
| Independent edits and invalid merged cycle | Converge or retain both inputs; explicit validated resolution and recovery. MergeTests/CoordinatorTests. |
| Backup/localStore/cloudSnapshot | Round trips; reject wrong identity/kind/version or missing metadata. FormatContractTests. |
| Old files alongside absent new store | Start empty; all old bytes untouched before and after saving new data. StorageTests. |
| Incompatible new store or cloud snapshot | Preserve bytes/state; block writes/uploads. StorageTests, FormatContractTests, CloudKit format tests. |
| Invalid import, recovery copy as portable input | Reject before replacement. FormatContractTests/AcceptanceTests. |
| New local data and recovery copies | Restart preserves review, account partitions, pending work and conflict inputs. StorageTests. |
| Forbidden module import/target connection; stale generator output/name | CI check fails, including newly added files. Checker negative tests. |
| Known, absent or unknown theme override | Select the requested known theme or preserve the developer default; ThemeTests. |
| Reduce Motion with either theme | No custom transition or press scaling; ThemeTests and rendered interaction check. |
| Default light/dark; TRON; navigation and nested sheets | Consistent inherited theme, readable text, native controls and unchanged commands; Apple builds and manual checks in THEMES.md. |
| Large text, long titles, disabled/destructive controls and Increased Contrast | Usable layout and labels, no glow under Increased Contrast; manual checks in THEMES.md. |

Unsigned builds and tests do not establish live iCloud operation. Apple identifier registration, signing/provisioning, CloudKit development/production schema deployment and signed two-device tests are release requirements.
