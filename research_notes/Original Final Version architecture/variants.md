> Historical reference. Source terminology is retained; this is not the current app specification. See [current product rules](../../docs/APP_RULES.md). [Retired code at its final pre-rename commit](https://github.com/vsodem/dotlist-plus/blob/4d96ce399c4a138288ffb6acb4459eacc34cb266/index.html).

# Original Final Version versus later variants

## Which dates and algorithm changes distinguish the versions?

### Takeaway

FVP changes both the question and rescanning. Fast FVP later permits acting during scanning. [FVP repost](https://markforster.squarespace.com/blog/2021/11/16/the-final-version-perfected-fvp-instructions-reposted.html); [Fast FVP revision](https://markforster.squarespace.com/blog/2018/1/6/change-to-fast-fvp.html)

### Cited Findings

- **Original FV: March 2012.** Forster announced release on **March 12, 2012**, initially distributing the instructions by newsletter over the following days. Do not label March 12 the exact instruction publication date on this evidence alone. [Forster's release announcement](https://markforster.squarespace.com/blog/2012/3/12/the-final-version-is-here.html)
- **Original question, explicitly confirmed August 14, 2023:** Forster personally answered a reader's before-versus-more query: “What do I want to do before I do x?” This is author testimony in a forum comment, not the reader's interpretation. [Forster comment, 21:44](https://markforster.squarespace.com/fv-forum/post/2794799)
- **FVP: May 21, 2015; reposted November 16, 2021.** Forster identifies it as an amended algorithm. Compare wanting another task **more than** the benchmark. After action, the preceding dot is the benchmark, but rescan after the actioned entry. Exact passage: “you check only the tasks which come after the task you have just done”. [FVP repost](https://markforster.squarespace.com/blog/2021/11/16/the-final-version-perfected-fvp-instructions-reposted.html); [retrieved blog text](https://markforster.squarespace.com/)
- **Fast FVP: verified in Forster's January 6, 2017 worked example.** Dot the first task; if ready, act immediately. Otherwise compare subsequent entries with the current benchmark. Each newly dotted task can be acted on immediately if ready. After action, consider the preceding surviving dot, then if needed scan after the entry just actioned. Forster's own **July 12, 2017** comment clarifies that comparison determines whether to dot, then readiness determines whether to act. His **March 29, 2018** comment explicitly rejects scanning from the remaining dot instead of from the actioned entry. [Forster's worked example and comments](https://markforster.squarespace.com/blog/2017/1/6/fast-fvp-an-example.html)
- **Fast FVP revision: January 6, 2018.** At a dot, either act or continue scanning. After acting, either act on the preceding dot or resume adding dots after the task just actioned. Delete/re-enter unfinished work at the bottom. The new first task must be dotted when the former first task is removed; at the end, act on the last dot. Selection wording is deliberately unspecified, and Forster says in his **January 6, 20:18** comment that he would use standing out. His **January 12, 2018** comment clarifies that the actioned task is always the **last** dotted task, never an arbitrary earlier dot. [Forster's revision and comments](https://markforster.squarespace.com/blog/2018/1/6/change-to-fast-fvp.html)
- **Alternative question: January 17, 2021.** Forster proposes considering resistance to the consequences of *not* doing a task. For comparison methods he gives: “What am I resisting NOT doing more than x?” This is explicitly later experimentation applying to FV/FVP, not original FV wording. [Forster's new-question article](https://markforster.squarespace.com/blog/2021/1/17/a-new-question-for-fvp-simple-scanning-and-life-in-general.html)
- **NQ-FVP documented April 22, 2022.** Forster explicitly traces the name from FV through FVP and says NQ means No Question. His description emphasizes intuitive readiness. [Forster's NQ-FVP Part 1](https://markforster.squarespace.com/blog/2022/4/22/some-aspects-of-nq-fvp-part-1.html)
- **Experimental NQ-FVP changes: May 3, 2022.** He proposes optionally acting on the preceding dot without rescanning to the end, and a maximum of **two new dots per scan**, excluding the root. He explicitly distinguishes this from two dots total. These were tentative experiments based on only three or four hours of use. Do not turn them into original FV rules. [Forster's suggested improvements](https://markforster.squarespace.com/blog/2022/5/3/some-suggested-improvements-to-nq-fvp.html)

### Inferences

- Architecture must distinguish the **comparison benchmark** from the **scan start**. In FVP these can be far apart; a single current-task pointer cannot safely stand for both. This is an implementation inference from the explicit FVP example, not Forster's data-model prescription. [Forster's example](https://markforster.squarespace.com/blog/2017/1/6/fast-fvp-an-example.html)
- Original FV should not gain an ordinary rescan after each action merely because an FVP explanation has been consulted. The parent's original-rule researcher has separately verified original chain execution in reverse; use that source in the final original specification.

### Gaps

- The December 21, 2016 initial Fast FVP article URL is referenced by other pages, but I did not retrieve its full authoritative text. January 6, 2017 is a verified explanation date, not claimed as Fast FVP's invention date.
- I did not establish the first publication date of NQ-FVP. April 22, 2022 is verified documentation, not its origin.
- Direct web opens of several canonical Squarespace articles returned internal errors. Search returned full author text, particularly the FVP repost embedded in his homepage. Preserve that retrieval limitation if needed; do not imply an original 2015 page was inspected.

## How do later urgent-task and restart provisions differ from original behavior?

### Takeaway

FVP distinguishes ordinary rescanning from discarding stale preselection and restarting. [Forster's FVP tips](https://markforster.squarespace.com/blog/2021/11/16/the-final-version-perfected-fvp-instructions-reposted.html)

### Cited Findings

- FVP permits restarting stale preselection. Append urgent work, or move existing urgent work to the bottom; the algorithm then considers it next, conditional on preference. [FVP repost, Additional Tips](https://markforster.squarespace.com/blog/2021/11/16/the-final-version-perfected-fvp-instructions-reposted.html)
- Original FV FAQ navigation confirms different framing: normally append incoming work; special handling is needed if it cannot wait for the current chain. It also lists reprioritization when selection is irrelevant. The indexed navigation truncates both answers, so use the parent's independently retrieved complete FAQ entries for exact mechanics. [Original FV FAQ index](https://markforster.squarespace.com/final-version-faqs/basic-system/)
- A later general author comment allows either home/office or work/personal list separation according to what suits the user. This **November 13, 2017** advice is broader than the original FAQ's location-based recommendation. [Forster's comment under What is a Task?](https://markforster.squarespace.com/blog/2017/11/9/what-is-a-task.html)

### Inferences

- A midnight reset does not follow from FVP's stale-preselection tip. [FVP tips](https://markforster.squarespace.com/blog/2021/11/16/the-final-version-perfected-fvp-instructions-reposted.html)

### Gaps

- This research did not recover the full original FAQ answers about urgent insertion and changing preselection; defer to the other researcher rather than infer the truncated sentences.

## Which similar names should be excluded from original FV?

### Takeaway

Similar titles may describe unreleased development, later Forster experiments, or reader inventions. Authorship and dates must be checked before importing their rules.

### Cited Findings

- **Final Version – Perfect at last!**, **October 14, 2011**, reports testing and plans to demonstrate the then-unreleased FV. It is not the **2015 FVP** instruction set despite the word Perfect. [Forster's 2011 post](https://markforster.squarespace.com/blog/2011/10/14/final-version-perfect-at-last.html)
- **No-List FVP**, documented **June 28, 2016**, is a later method focused on currently chosen work. Forster says its next action is always the last list entry and that unfinished work need not be rigidly re-entered. Do not confuse No-List FVP with **No-Question FVP**. [Forster's article](https://markforster.squarespace.com/blog/2016/6/28/more-about-no-list-fvp.html)
- **Fast Final Version**, forum post **July 26, 2016**, was written by **nuntym**, not Forster. It is therefore excluded from this author-only rule history except to flag misattribution. [Forum attribution](https://markforster.squarespace.com/fv-forum/post/2619857)
- **Getting more focus with FVP / Anchored FVP** is a **Seraphim** proposal, originally **December 9, 2015**. Forster's participation in the discussion does not make all reader rules his own instructions. [Thread and author labels](https://markforster.squarespace.com/fv-forum/post/2560976)

### Inferences

- Label the intended app method **Original Final Version (2012)** in architecture, and keep later alternatives in an explicit exclusion/comparison note. This follows the documented divergence above; it is a design recommendation, not a claim that Forster used that exact product label.

### Gaps

- This is a targeted disambiguation of likely confusions, not an exhaustive history of every Forster system and reader variant.
