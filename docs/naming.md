# Dot List Plus naming inventory

Use **Dot List Plus** in displayed names, **DotListPlus** in code identifiers and **dot-list-plus** in readable filenames. The repository remains `dotlist-plus`.

| Term | Definition |
|---|---|
| Project | A named collection of related work. |
| Outcome | A result completed through required actions; an empty outcome is incomplete. |
| Action | Work that can receive a dot and be performed. |
| Work item | An outcome or action collectively. |
| Prerequisite | An action that must finish before another becomes available. |
| Review | Comparing a fixed set of available actions to choose dots. |
| Dotted chain | Actions in selection order, performed in reverse order. |
| Selection state | Phase, dotted chain, review candidates and candidate position. |
| List state | One list's projects, work items, action order and selection state. |
| Local store | Account-separated lists and durable synchronization information. |
| Portable backup | One list without account or provider metadata. |
| Recovery copy | Complete local store retained before replacement. |

| Historical name | Maintained name |
|---|---|
| WorkTask / tasks / task() | WorkItem / workItems / workItem() |
| group / groupProgress | outcome / outcomeProgress |
| TaskRules / Progress | WorkItemRules / WorkProgress |
| AppState / Selection / Change | ListState / SelectionState / ListChange |
| SelectionRules | ListRules.transition / ListRules.validateSelection |
| projectId / parentId / prerequisiteIds | projectID / outcomeID / prerequisiteIDs |
| chain / candidates / cursor | dottedActionIDs / candidateActionIDs / candidateIndex |
| SyncView / coordinator view() | CoordinatorSnapshot / snapshot() |
| StoredLists / AccountList | LocalStoreState / AccountListState |
| TaskEditor / WorkView / BreakdownView | WorkItemEditor / AllWorkView / OutcomeConversionView |
| addTask / renameTask / relationships / deleteTask | addWorkItem / renameWorkItem / updateRelationships / deleteWorkItem |
| reopen / breakDown | reopenAction / convertActionToOutcome |
| answer / complete / partial / urgent | answerReview / completeNextAction / recordPartialWork / makeUrgent |
| chooseAgain / eraseAll | clearSelection / eraseCurrentList |
| DotList / DotListCore / DotListStorage | DotListPlus / DotListPlusCore / DotListPlusStorage |

`beginReview` retains its name, as do `idle`, `reviewing`, `executing`. `reviewBenchmark` is available only while reviewing; `nextAction` only while executing. Interface names include Required actions, Convert to outcome, Start review and Erase current list. Project commands remain addProject, renameProject and deleteProject. WorkProgress.complete is a progress value, not a command.

## Historical and framework exceptions

The checker has an explicit file allowlist for this mapping, the original research report, two research notes and the dated iCloud implementation plan. Those documents retain source terminology for attribution and are marked historical; they are not current instructions.

Swift `Task`, task groups, `addTask`, SwiftUI `.task`, `Group`, Xcode `PBXGroup` and SDK API names retain framework spelling. Negative tests retain narrowly identified old-format fixtures and forbidden-name examples to prove rejection. Git hooks use “task” in its ordinary automation sense. The repository name and immutable GitHub URLs remain unchanged. No production alias keeps the old domain names or old serialized fields working.
