# Dot List Plus: current implementation and practical edit points

## What exists in this checkout?

### Takeaway
The current checkout is the original single-file browser demo, despite its directory and branch names. There is no current `plus.html`, `serve.py`, native app, or runnable test suite to map.

### Cited Findings
- `README.md` identifies `index.html` as the whole app, runnable directly or through a static server. — [README.md](/Users/vsodem/Experiments/dotlist-plus/README.md:5)
- The file has four sections: state/persistence, algorithm, rendering, and events. — [index.html](/Users/vsodem/Experiments/dotlist-plus/index.html:273)
- Current Git inspection on 2026-10-15: branch `dot-list-plus-m0`, HEAD `72be0c0`; `git ls-files` lists only `.nojekyll`, `README.md`, `index.html`. `plus.html`, `serve.py`, test source files, and `package.json` are absent. Untracked test-result folders and Python bytecode are leftover evidence, not current source or passing tests. This observation comes from filesystem and Git commands, not a clickable source file.
- Another branch, `dot-list-plus-m1`, contains design and plan documents describing a Plus daily driver and native architecture. Those are not files in the current checkout and do not establish that implementation exists here. No branch was switched and no source was changed.

### Inferences
- Treat `/index.html` as the only verified entry point. Do not claim `/plus.html` currently runs or that its behavior was examined. A future implementation must first locate or restore that source if Plus-specific changes are intended.

### Gaps
- No applicable AGENTS.md was found in the checkout or checked parent directories; user-provided AGENTS instructions were followed.
- No current source tests were available. Six narrow in-memory assertions were run against the actual `index.html` functions with synthetic A/B/C/D/U tasks, rendering and persistence disabled. All passed; this checks state transitions, not browser rendering or storage. Private task files and browser storage were not read.

## What does task selection actually do?

### Takeaway
The normal loop builds a chain by scanning downward, works its dots in reverse selection order, and starts a fresh chain only when that chain is exhausted. It does **not** require a new comparison pass after every task; the coordinator's original-2012 source research says that is consistent with original FV.

### Cited Findings
| Concern | Actual behavior | Source |
|---|---|---|
| Task order and state | Array order is list order. Each task has `id`, `text`, `dotted`, `dotOrder`, `doneAt`, `addedAt`. State also stores `mode` and an array-index `reviewCursor`. | [state shape](/Users/vsodem/Experiments/dotlist-plus/index.html:287) |
| First dot | `freshState` dots the top active task with order 0. `recomputeAnchor` adds this anchor only if no active dot has order 0. | [freshState](/Users/vsodem/Experiments/dotlist-plus/index.html:307), [recomputeAnchor](/Users/vsodem/Experiments/dotlist-plus/index.html:378) |
| Review start | `startReview` finds the highest-order active dot and scans below it. Normally that is the initial anchor; after urgent add it may be the urgent task. | [startReview](/Users/vsodem/Experiments/dotlist-plus/index.html:608) |
| Candidate scan | `nextCandidateIndex` visits active undotted tasks strictly below a supplied array index. It never wraps to the top. | [nextCandidateIndex](/Users/vsodem/Experiments/dotlist-plus/index.html:392) |
| Yes | Dots the candidate, gives it the next order, makes it the benchmark, and continues downward. Earlier dots remain. | [reviewYes](/Users/vsodem/Experiments/dotlist-plus/index.html:623) |
| No | Moves below the current candidate, keeping the benchmark. The skipped task stays undotted in its original position. | [reviewNo](/Users/vsodem/Experiments/dotlist-plus/index.html:640) |
| Question | Current UI asks whether you want to do the candidate “more than” the benchmark. This is a specific phrasing choice, distinct from the original “before” framing. | [renderPrompt](/Users/vsodem/Experiments/dotlist-plus/index.html:478) |
| Work order | Highest `dotOrder` is both the review benchmark and next action. This is reverse dot order; ordinarily also bottommost dot first. | [benchmarkIndex](/Users/vsodem/Experiments/dotlist-plus/index.html:402) |
| After an action | `completeCurrent` resolves the current dot. If any dots remain, mode stays `executing` and the next one is shown directly. No new scan. | [completeCurrent](/Users/vsodem/Experiments/dotlist-plus/index.html:660) |
| Unfinished work | “Started, not done” resolves the old entry and appends a new undotted copy with a new ID at the bottom. Pending earlier dots stay selected. | [partial branch](/Users/vsodem/Experiments/dotlist-plus/index.html:668) |
| Empty chain | Switches to `idle`, anchors the first remaining active task, and waits for “Start review.” If no tasks remain, switches to `empty`. | [completion tail](/Users/vsodem/Experiments/dotlist-plus/index.html:673) |
| Urgent addition | Appends a task already dotted with the highest order. During execution it immediately replaces the displayed next action; it is not queued behind a separately tracked in-progress task. During review it immediately becomes the benchmark while the existing candidate cursor stays where it was. In idle, Start review begins below the newly appended urgent task, usually entering execution immediately. | [addTask](/Users/vsodem/Experiments/dotlist-plus/index.html:570), [benchmarkIndex](/Users/vsodem/Experiments/dotlist-plus/index.html:402), [startReview](/Users/vsodem/Experiments/dotlist-plus/index.html:608) |
| Early review exit | “End review” executes the dots selected so far even if unexamined candidates remain below. | [button](/Users/vsodem/Experiments/dotlist-plus/index.html:485), [finishReview](/Users/vsodem/Experiments/dotlist-plus/index.html:653) |
| Out-of-order action | Every active task has a completion shortcut; `completeTask(id)` can resolve a task other than next-up. | [completeTask](/Users/vsodem/Experiments/dotlist-plus/index.html:687) |
| Reload/resume | Saves all state as `dotlist-v1` in localStorage and loads it on boot, including dots/mode/cursor. Boot also calls `recomputeAnchor`. No day boundary reset exists. | [load/save](/Users/vsodem/Experiments/dotlist-plus/index.html:330), [boot](/Users/vsodem/Experiments/dotlist-plus/index.html:787) |
| Reset/restart | “Reset” confirms wiping the entire list and sets an empty state. This is not a safe “reconsider my remaining dots” action. README says Reset reloads demo tasks, but implementation empties the list; loading demo is a separate empty-state button. | [resetAll](/Users/vsodem/Experiments/dotlist-plus/index.html:728), [empty prompt](/Users/vsodem/Experiments/dotlist-plus/index.html:441), [README mismatch](/Users/vsodem/Experiments/dotlist-plus/README.md:17) |

### Inferences
- Concrete verified example: list A/B/C/D; dot A automatically, Yes B, No C, Yes D. Work D then B then A. If B is only started, append a fresh B; after A, the remaining list is C/B and C becomes the next anchor. Six synthetic runtime assertions confirmed these transitions, urgent preemption, and Reset emptying.
- A missing capability for optional stale-chain review is a visible “Review below this dot” action during execution. `startReview` already scans below the highest remaining dot and preserves prior dots, but only the idle UI and idle keyboard shortcut currently expose it. — [executing UI](/Users/vsodem/Experiments/dotlist-plus/index.html:495), [keyboard handling](/Users/vsodem/Experiments/dotlist-plus/index.html:769)
- Do not call the absence of automatic re-review after each action a bug in original FV. Distinguish a user-requested variant from method fidelity.
- `addTask`'s comment says an urgent task is next “after current,” but actual execution has no separate current task: the urgent task immediately becomes next-up. Runtime assertion verified this. — [comment and implementation](/Users/vsodem/Experiments/dotlist-plus/index.html:575)

### Gaps
- No browser UI test or persistent-state resume test was run. Resume conclusions are code inspection.
- Source parity should be judged against the original method sources collected by the other researchers, not README's label alone.

## How can the selection method remain easy to edit?

### Takeaway
Proposal only: keep the existing four-section structure and make the few relevant functions explicit edit points. No configurable rule engine or large framework is needed for this app.

### Cited Findings
| Desired change | Smallest current edit point |
|---|---|
| Use “before” instead of “more than” | `renderPrompt`, especially lines 478–481; synchronize help text and README. [source](/Users/vsodem/Experiments/dotlist-plus/index.html:478) |
| Change which task starts a chain | `recomputeAnchor`. [source](/Users/vsodem/Experiments/dotlist-plus/index.html:378) |
| Change eligible candidates or scan direction | `nextCandidateIndex`, with `startReview` controlling the starting point. [source](/Users/vsodem/Experiments/dotlist-plus/index.html:392) |
| Change what Yes/No means | `reviewYes` and `reviewNo`; preserve candidate-relative skip advancement. [source](/Users/vsodem/Experiments/dotlist-plus/index.html:623) |
| Change when to reconsider pending dots | `completeCurrent` tail, corresponding `completeTask` tail, and execution controls in `renderPrompt`. [completion](/Users/vsodem/Experiments/dotlist-plus/index.html:673), [out-of-order completion](/Users/vsodem/Experiments/dotlist-plus/index.html:706), [controls](/Users/vsodem/Experiments/dotlist-plus/index.html:495) |
| Change urgent insertion | `addTask`; explicitly account for its shared effect on both benchmark and next action. [source](/Users/vsodem/Experiments/dotlist-plus/index.html:570) |
| Change unfinished-task handling | Partial branch in `completeCurrent`. [source](/Users/vsodem/Experiments/dotlist-plus/index.html:668) |
| Change persistence/reset | `load`, `save`, `resetAll`, boot. [source](/Users/vsodem/Experiments/dotlist-plus/index.html:330), [reset](/Users/vsodem/Experiments/dotlist-plus/index.html:728) |

### Inferences
- Minimal proposal for closer original-FV wording and optional rescan: change the comparison wording; add a button in execution that calls existing `startReview`; describe Reset accurately. Keep chain execution unchanged. This is a proposal, not implemented work.
- If substantial future variants require changes, extract just state and action functions into a small `fv-engine.js`, with rendering/storage as callers. Only do that when needed; current single-file sections already make small edits practical.
- Before any behavioral edit, preserve narrow scenario checks: skipped candidates advance; Yes retains older dots; D/B/A reverse order; partial copies append undotted; urgent task becomes next-up; chain exhaustion anchors first remaining task; reload retains pending dots. Add a stale-chain rescan check only if that control is implemented.
- Separate actual defects from method choices: array-index cursors can shift when items are deleted, and unconditional anchor repair in add/delete/boot can introduce a dot mid-chain after the original anchor is removed. These are implementation concerns, not reasons to silently change FV. — [deleteTask](/Users/vsodem/Experiments/dotlist-plus/index.html:591), [addTask](/Users/vsodem/Experiments/dotlist-plus/index.html:586), [boot](/Users/vsodem/Experiments/dotlist-plus/index.html:789)

### Gaps
- No implementation was requested or performed. Source, branches, stored tasks, and existing untracked files remain unchanged. Only these research notes were added.
