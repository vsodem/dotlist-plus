# Dotlist app architecture

Status: specification for implementation; app code has not been changed.

This document defines a dot-list app with projects, broad tasks, actionable substeps, and prerequisites. It is written for both the person editing the rules and Codex implementing them. Change the rules here before changing behavior in code.

## 1. Decisions and scope

**Agreed decisions**

- A prerequisite expresses something that must be finished before another action becomes available.
- A broad task can contain smaller actions. Containment does not imply an execution order.
- Review presents available actions with their parent label, rather than presenting the broad parent for selection.
- Completing a prerequisite makes dependent actions available, but they wait for the next review. They do not enter the existing dotted chain.
- Partially working on a prerequisite does not satisfy it.

**Proposed defaults**

The remaining rules make these decisions implementable. They are explicit defaults, not additional decisions already approved by the user:

- Use the original FV comparison question and reverse-chain execution.
- Require every prerequisite to be complete. No alternative-prerequisite conditions in the first version.
- Treat every child included in a broad task as required. Optional work remains outside that parent's completion requirements.
- Allow one level of broad tasks within a project; defer nested broad tasks and cross-project prerequisites.
- Preserve browser-local storage and the current lightweight app. No backend, accounts, or sync is required by this specification.

The existing [research and code map](../reports/Original%20Final%20Version%20architecture.md) distinguishes original FV from later variants. Projects and dependency handling here are our extension, not rules attributed to Forster.

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

Rules 3 and 4 are essential: the current app finishes an old entry and creates a new one for partial work. That would falsely satisfy prerequisites if copied into this design.

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

## 5. Selection and execution

### Begin a review

From `idle`, capture available actions in `actionOrder` order. If none exist, stay idle and show blocked work or groups needing breakdown. Show “No remaining work” only when neither remains. Never dot a blocked action to force progress.

Otherwise, set `candidates` to that snapshot, dot its first action by putting its ID in `chain`, and set `cursor = 1`. If there is only one candidate, enter execution immediately.

For each later candidate, ask: **“Do I want to do [candidate] before [last dotted action]?”** Yes appends its ID to the chain. No leaves the chain unchanged. Both advance the cursor. At the end, enter execution and clear the candidate snapshot and cursor.

### Complete an action

Finish only the last action in the chain. Set its completion timestamp, remove its ID from `actionOrder`, and remove its dot. Recalculate availability and group progress.

If dots remain, continue executing them. Newly available actions remain undotted. If no dots remain, enter `idle` and offer the next review. Do not silently start selecting a new chain.

### Work without finishing

Remove the last dot, leave the action incomplete, and move its existing ID to the bottom of `actionOrder`. Preserve all relationships. Continue the remaining chain, or return to idle if it is empty. No dependent action is unlocked.

### Other changes during a cycle

New ordinary actions are appended undotted and wait for the next review. Titles may be edited at any time.

For the first implementation, changes to prerequisites, parent membership, deletion, and reopening completed work require returning to idle through the explicit “Choose again” operation. This keeps the selected chain valid. Do not silently discard a selection when editing a title or adding ordinary work.

The first implementation does not offer out-of-order completion during a review or execution cycle. That existing demo shortcut would need separate rules before being retained.

### Break an existing action into substeps

While idle, an unfinished action without a parent can become a broad task with one or more required child actions. Keep the original ID for the group; give each child a new ID and the same project. Replace the old action's position in `actionOrder` with the children in the user's chosen order. This list order does not itself create prerequisites. Breaking down an existing child would require nested groups, which are outside this version.

Transfer the original prerequisites to every child. For each action that depended on the original, replace that link with links to all the children. Clear the group's prerequisite list. Validate and save the whole change together. Show these transferred relationships before applying the breakdown. These are explicit action links: adding a child later changes group progress but does not silently add prerequisites to other actions.

## 6. Urgent work and restarting

**Urgent available action:** append or move its ID to the bottom of `actionOrder`, remove any existing occurrence from the chain, then append it once to the chain. It becomes next-up. From idle, enter execution. During execution, preserve the other dots.

If urgent insertion happens during review, end that review, retain the dots already selected, and execute the urgent action first. Discard the remaining candidate snapshot. Unreviewed actions wait for the next review. This is a proposed app rule to avoid changing the benchmark while retaining a misleading cursor.

The app tracks a next action, not a timed work session. Urgent insertion changes next-up immediately; it cannot determine whether the person has physically stopped working.

**Urgent blocked action:** follow its prerequisite links to show available prerequisite actions, and let the user explicitly choose one to make urgent. Do not dot the blocked action or choose a prerequisite automatically. Completing that prerequisite still leaves the dependent action waiting for review. Urgency does not propagate automatically.

| Operation | Effect |
|---|---|
| Resume | Restore the saved phase, dots, candidates, and cursor. |
| Next review | From idle, begin a fresh availability snapshot. |
| Choose again | Clear selection state and return to idle; preserve tasks, relationships, completion, and list order. |
| Erase all data | After explicit confirmation, clear tasks, projects, and selection. |

Keep these controls distinct. A specialized rescan below the remaining dot is outside this first implementation; “Choose again” always starts fresh.

## 7. Worked examples

### Lunch with an existing dotted chain

List order: Reply to Alex, Buy groceries, Cook lunch. Cooking requires groceries. At review start, candidates are Reply to Alex and Buy groceries; cooking is excluded.

Reply to Alex is dotted first. Answer Yes to doing Buy groceries before Reply to Alex. The chain is now Reply to Alex, Buy groceries, so groceries runs first. Finish groceries. Cooking becomes available, but it is not dotted. Reply to Alex remains next. After replying, the chain is empty and the next review includes cooking.

If groceries had been the only dot, the next review would be offered immediately after completing it. Starting groceries without finishing them would leave cooking blocked.

### Cleaning with both containment and order

`Clean room` contains Organize belongings, Sweep floor, and Mop floor. Only Mop floor requires Sweep floor. Organizing has no prerequisite.

Review can offer Organize belongings and Sweep floor independently, with `Clean room` in both labels. Finishing sweeping makes mopping available for the next review. Finishing mopping does not complete the group while organizing remains unfinished.

### Partial work preserves the link

Buy groceries has ID `groceries`; Cook lunch depends on `groceries`. After partial work, move `groceries` to the bottom without changing its ID or completion timestamp. Cooking still depends on the same unfinished action. Completing `groceries` later satisfies the link.

## 8. Implementation boundaries

Keep three responsibilities separate, even if they initially remain sections of one file:

| Responsibility | Owns |
|---|---|
| Task rules | Relationships, validation, availability, derived group progress |
| Selection rules | Review snapshot, dots, Yes/No, completion, partial work, urgent insertion, choosing again |
| Interface and storage | Labels, buttons, blocked explanations, saving and restoring state |

Task and selection functions accept state and an action, and return the next state or a clear validation error. They must not read the DOM or browser storage. Apply each change as one state transition, then save and render it. This makes the rules testable without a browser and editable without redesigning the UI.

In the current [index.html](../index.html), the main changes are:

- `makeTask`, `load`, and `save`: introduce the new saved model and migration.
- `activeTasks`, `recomputeAnchor`, and `nextCandidateIndex`: distinguish unfinished work from available work; create dots only when review begins.
- `chain`, `benchmarkIndex`, `startReview`, `reviewYes`, and `reviewNo`: use the explicit chain and candidate snapshot.
- `completeCurrent`: preserve identity on partial work and unlock without inserting dots.
- `addTask`, `deleteTask`, and `completeTask`: apply the mutation rules above rather than bypassing them.
- `renderPrompt` and list rendering: show parent labels and blocked reasons; use the original comparison wording.
- `resetAll` and `clearCompleted`: separate erasing data from hiding completed work. Never delete a completed prerequisite merely to clean up the display.

No new framework is required. Split the rule functions into a small module only if that makes testing and maintenance easier.

## 9. Validation, storage, and migration

Reject missing references, duplicate prerequisite IDs, self-dependencies, cycles, group prerequisites, invalid parent types, and cross-project links. Deleting a referenced prerequisite must fail with an explanation; let the user explicitly change the relationship first. A nonempty group cannot be deleted until its children are moved or removed.

Reopening an action with completed dependents requires first reopening those dependents. Do not retain an impossible completion order. Reopening is available only while idle and appends the reopened action to `actionOrder`.

Persist the entire state after a successful transition. On reload, validate it before resuming. If task data is valid but selection state is invalid, preserve the tasks, clear selection, and explain that a new review is needed. If task data is invalid, retain the original saved data and show a recovery error; do not replace it with demo tasks. Surface save failures so the user knows changes are not yet durable.

For existing `dotlist-v1` data:

1. Preserve an untouched copy under the old storage key. Write version 2 to a new key only after validation succeeds.
2. Import each entry as a standalone action with its existing ID, title, and completion timestamp. Use existing active list order for `actionOrder`.
3. Do not guess relationships between old completed entries and similarly named unfinished copies.
4. Begin idle with no dots and explain the one-time selection reset. Future version-2 reloads resume normally.

## 10. Acceptance checks

These are scenarios Codex must turn into behavior tests when implementing. They are not claims that the current app passes them.

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

## 11. Editing this specification

For behavioral changes, edit the relevant rule and its acceptance check together. Keep agreed decisions in section 1 distinct from defaults. Do not let a UI shortcut silently introduce a different selection algorithm.

Implementation is complete only when the rules, interface, migration, and acceptance checks agree. Scheduling, recurring work, multi-device sync, nested groups, automatic prerequisite generation, and alternative prerequisite conditions are outside this specification.
