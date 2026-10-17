> Historical reference. Source terminology is retained; this is not the current app specification. See [current product rules](../docs/APP_RULES.md). [Retired code at its final pre-rename commit](https://github.com/vsodem/dotlist-plus/blob/4d96ce399c4a138288ffb6acb4459eacc34cb266/index.html).

# Keep original Final Version easy to edit

**The current app combines original Final Version's execution loop with a later question wording.** Changing that wording is a smaller correction than replacing the algorithm. This report separates Mark Forster's published method, later variants, and the behavior verified in this checkout. The practical goal is a short set of rules with named places to edit them, without adding a configurable framework. No application code was changed.

## Original FV selects before it executes

Forster announced Final Version in March 2012 and distributed its instructions through his newsletter. The March 13 newsletter is the original specification used here. In a later answer explicitly about FV, he confirmed the question: **“What do I want to do before I do x?”** The distinction between *before* and *more* matters: his original FAQ warns against substituting the latter. ([Release announcement](https://markforster.squarespace.com/blog/2012/3/12/the-final-version-is-here.html), [Original newsletter](https://archive.constantcontact.com/fs004/1100358239599/archive/1109511856508.html), [Author's clarification](https://markforster.squarespace.com/fv-forum/post/2794799), [FAQ](https://markforster.squarespace.com/final-version-faqs/))

Dots mark selected work awaiting action, not completion or permanent priority. Adding a dot preserves earlier dots. Dot the first unactioned task. Scan downward using the question above. The first qualifying task becomes the new dotted comparison; continue below it. At the bottom, work dots backwards without routine rescanning. Cross out actioned entries, append unfinished work, and restart after exhausting the chain. ([Original instructions](https://archive.constantcontact.com/fs004/1100358239599/archive/1109511856508.html))

Append and dot urgent work, moving existing entries when necessary. Reconsider stale selection from the beginning or last remaining dot. Move unavailable first tasks to the bottom; delete irrelevant entries. ([Original instructions](https://archive.constantcontact.com/fs004/1100358239599/archive/1109511856508.html))

**Constructed example:** A/B/C/D; dot A, skip B, dot C, skip D. Work C, then A. Append unfinished C as C′. After A, restart at B. ([Rule source](https://archive.constantcontact.com/fs004/1100358239599/archive/1109511856508.html))

**Constructed urgent example:** A/C dotted; append dotted U. Work U/C/A. ([Rule source](https://archive.constantcontact.com/fs004/1100358239599/archive/1109511856508.html))

## Interruptions and restarting require different actions

Forster's FAQ says ordinary incoming tasks join the bottom and that, after an interruption, you return to the same place. It prescribes no standard chain length. Fixed-time appointments sit outside this system for choosing discretionary work. His separate advice about making at least three passes on an ordinary day is practical guidance, not a mandatory reset schedule. ([FAQ](https://markforster.squarespace.com/final-version-faqs/), [Review-frequency advice](https://markforster.squarespace.com/final-version-faqs/basic-system/does-it-matter-how-often-i-go-through-the-list.html))

**Constructed interruption and restart example:** a phone call interrupts a selected task. After the call, resume there. If the call changes what needs doing, reconsider the selection. That does not require deleting the task list. The first behavior follows the FAQ; the distinction between selection and stored data is an application design interpretation. ([FAQ](https://markforster.squarespace.com/final-version-faqs/))

For the app, four operations need distinct names: resume saved work, reconsider selected dots, rewrite task entries, and erase all tasks. **No mandatory daily restart was established by the sources reviewed.** A daily restart would therefore be a personal adaptation requiring its own explanation. The current Reset control performs the fourth operation: it empties the list after confirmation. It does not just clear dots. README currently says Reset reloads the demo, which disagrees with the code. ([Reset implementation](/Users/vsodem/Experiments/dotlist-plus/index.html:728), [README](/Users/vsodem/Experiments/dotlist-plus/README.md:17))

## Later names describe different decisions

| Version and verified date | Distinguishing behavior |
|---|---|
| Original FV, March 2012 | The baseline rules above. ([Instructions](https://archive.constantcontact.com/fs004/1100358239599/archive/1109511856508.html)) |
| Final Version Perfected, May 2015; reposted November 2021 | Uses *more than*. After action, the preceding surviving dot becomes the comparison benchmark, but scanning begins **after the just-actioned entry**, not after that surviving dot. ([FVP instructions](https://markforster.squarespace.com/blog/2021/11/16/the-final-version-perfected-fvp-instructions-reposted.html)) |
| Fast FVP, explained January 2017 | Permits acting on a newly dotted task immediately when ready. Readiness and the comparison decision are separate. After action, the surviving dot and the scan starting position can still differ. ([Author's example and clarifications](https://markforster.squarespace.com/blog/2017/1/6/fast-fvp-an-example.html)) |
| Revised Fast FVP, January 2018 | Allows acting on the preceding dot or resuming selection after the actioned entry. Its flexibility does not redefine earlier FV instructions. ([Revision](https://markforster.squarespace.com/blog/2018/1/6/change-to-fast-fvp.html)) |
| No-Question FVP, documented April 2022 | Emphasizes intuitive readiness. May 2022 experiments include at most two new dots per scan, excluding the root; these were tentative changes. ([Description](https://markforster.squarespace.com/blog/2022/4/22/some-aspects-of-nq-fvp-part-1.html), [Experiments](https://markforster.squarespace.com/blog/2022/5/3/some-suggested-improvements-to-nq-fvp.html)) |

The architecture consequence is specific: an FVP implementation must distinguish **which task is the comparison benchmark** from **where scanning resumes**. That is an inference from the method, not a data structure Forster prescribed. Substituting FVP behavior would be a variant choice; the current lack of automatic rescanning is not an original-FV bug.

Names also need attribution checks. Forster's 2011 post containing “Perfect at last!” predates release and is not the 2015 FVP specification. No-List FVP is distinct from No-Question FVP. A forum post titled “Fast Final Version” was written by the reader nuntym, not Forster. ([2011 post](https://markforster.squarespace.com/blog/2011/10/14/final-version-perfect-at-last.html), [No-List FVP](https://markforster.squarespace.com/blog/2016/6/28/more-about-no-list-fvp.html), [Reader proposal](https://markforster.squarespace.com/fv-forum/post/2619857))

## The current app has small, identifiable edit points

The inspected checkout is the single-file `index.html` demo. No current `plus.html`, native app source, or test suite was available. The folder name does not establish that a separate Plus implementation exists. The file already separates state, algorithm, rendering, and events, which is adequate for modest personal changes. ([App structure](/Users/vsodem/Experiments/dotlist-plus/index.html:270), [README](/Users/vsodem/Experiments/dotlist-plus/README.md:5))

| Concern | Current behavior and smallest edit point |
|---|---|
| Stored state | Task array order is list order. Tasks store identity, text, dot status/order, and timestamps; mode and review cursor are saved with them. Edit [state and persistence](/Users/vsodem/Experiments/dotlist-plus/index.html:287). |
| Starting selection | The first active task receives dot order zero. Review starts below the highest-order active dot. Edit [recomputeAnchor](/Users/vsodem/Experiments/dotlist-plus/index.html:378) and [startReview](/Users/vsodem/Experiments/dotlist-plus/index.html:608). |
| Review decisions | Yes adds a dot and changes the benchmark; No advances past the candidate without moving it. Scanning never wraps. Edit [candidate selection](/Users/vsodem/Experiments/dotlist-plus/index.html:392), [Yes](/Users/vsodem/Experiments/dotlist-plus/index.html:623), and [No](/Users/vsodem/Experiments/dotlist-plus/index.html:640). |
| Comparison wording | The prompt currently uses *more than*. Edit [renderPrompt](/Users/vsodem/Experiments/dotlist-plus/index.html:478), then align help text and README. |
| Execution and unfinished work | Highest dot order runs next. “Started, not done” resolves the old entry and appends a fresh undotted copy. Remaining dots execute directly. Edit [completeCurrent](/Users/vsodem/Experiments/dotlist-plus/index.html:660). |
| Urgent additions | The appended task gets the highest dot order. During execution, it immediately replaces the displayed next action. During review, it changes the benchmark while leaving the candidate cursor in place. Edit [addTask](/Users/vsodem/Experiments/dotlist-plus/index.html:570). |
| Manual exceptions | End review starts execution early; per-task completion allows out-of-order action. Edit [review controls](/Users/vsodem/Experiments/dotlist-plus/index.html:482) and [completeTask](/Users/vsodem/Experiments/dotlist-plus/index.html:687). |
| Resume and erase | Browser storage retains dots, mode, and cursor. Boot repairs the initial dot; there is no day-boundary reset. Edit [load/save](/Users/vsodem/Experiments/dotlist-plus/index.html:330), [boot](/Users/vsodem/Experiments/dotlist-plus/index.html:787), and [resetAll](/Users/vsodem/Experiments/dotlist-plus/index.html:728). |

The urgent-add comment promises action after the current task, but the code has no separate record of an in-progress task: it changes next-up immediately. Also, `startReview` can reconsider below a surviving dot, but execution controls do not expose that operation. These details matter when choosing button labels and expected behavior. ([Urgent implementation](/Users/vsodem/Experiments/dotlist-plus/index.html:575), [Execution controls](/Users/vsodem/Experiments/dotlist-plus/index.html:495))

## Proposed changes should stay small and explicit

**Proposals only:** use the original question, offer an explicit reconsider-selection control, and rename or describe Reset as erasing the list. Retain the existing normal execution order. A reconsider control could use the existing `startReview` function for review below the remaining dot; a full fresh selection needs separate handling of existing dots. These are different operations and should not share an ambiguous button.

Keep this report as the editable rule reference and the table as its code map. There is no demonstrated need to extract a framework. Before changing behavior, check a few concrete cases: skipped candidates advance, earlier dots survive Yes, unfinished copies append undotted, urgent additions change next-up, and saved state resumes correctly. Six narrow in-memory assertions passed during research; they covered selection, reverse execution, unfinished work, urgent addition, and Reset. They did not test browser rendering or persistence.

Several Squarespace pages failed direct retrieval; their available author text was retrieved through search indexing, and truncated FAQ continuations were not treated as evidence. Code observations refer to this checkout on October 15, 2026. Neither a separate Plus implementation nor a future adaptation is represented as completed work.
