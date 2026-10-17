> Historical reference. Source terminology is retained; this is not the current app specification. See [current product rules](../../docs/APP_RULES.md).

# Original Final Version: primary-source rules

## What exactly did the original algorithm require?

### Takeaway
Original FV uses a selected chain followed by reverse execution. A mandatory review between worked tasks is not its normal rule.

### Cited Findings
**S1 — Mark Forster, Final Version newsletter, March 13, 2012.** Full original newsletter was successfully fetched. Web source allowance: **200 derived words total**, quotations **25 words maximum**. Keep the final document's entire S1-derived explanation, examples, inferences and repetitions within that allowance. [Original newsletter](https://archive.constantcontact.com/fs004/1100358239599/archive/1109511856508.html).

Compact source summary (approximately 150 words; use this as the principal S1 budget):

- Dot the first unactioned entry. Scan forward in list order; the first qualifying entry becomes the next dotted benchmark. Continue comparing against that new benchmark. Stop selection when nothing later qualifies. Work through the dotted entries in reverse order; then start another chain at the first unactioned entry. Work need not finish a task: cross out the worked entry and append unfinished work. [S1](https://archive.constantcontact.com/fs004/1100358239599/archive/1109511856508.html)
- A stale chain may be replaced from the beginning, or reconsidered from its last remaining dotted entry. This is an exception, not an automatic step after every worked entry. Urgent additions go to the end and receive dots; existing entries becoming urgent move there. An unavailable root is crossed out and appended. Irrelevant entries can be deleted. [S1](https://archive.constantcontact.com/fs004/1100358239599/archive/1109511856508.html)

**S2 — Mark Forster's dated forum answer, August 14, 2023, 21:44.** The official FV question is **“What do I want to do before I do x?”** This is 12 quoted words; do not quote other text from S2 beyond the remaining 13-word allowance. Web source allowance 200 words. [Author clarification](https://markforster.squarespace.com/fv-forum/post/2794799).

**S3 — Release announcement, March 12, 2012, 02:36.** Forster announced that the free FV instructions would be distributed through a new newsletter over the following days. This establishes provenance for S1 rather than treating the newsletter as an unofficial retelling. Web allowance 200 words. [Release announcement](https://markforster.squarespace.com/blog/2012/3/12/the-final-version-is-here.html).

### Inferences
- Constructed trace, **not Forster's example**: ordered A/B/C/D; dot A, reject B, dot C, reject D; work C then A. (Count these words toward S1's allowance.)
- “First qualifying” ends the comparison with the old benchmark; it does **not** end the whole selection pass. Keep this distinction explicit. [S1](https://archive.constantcontact.com/fs004/1100358239599/archive/1109511856508.html)

### Gaps
- The original text describes cognitive selection, not a formal computer state machine. Field names, persistence rules, immutable identifiers, and button behavior must be labeled implementation choices.
- Original long worked example was read in full. It should **not** be reproduced alongside this explanation because S1's 200-word allowance is nearly used. Use an independently constructed minimal trace instead, or let the reader inspect the linked source.

## What clarifications apply to ordinary interruptions, task handling and chain changes?

### Takeaway
The author permits practical exceptions when circumstances change. He does not turn every interruption into a new selection cycle.

### Cited Findings
**S4 — Author's Final Version FAQ index, Basic System; individual dates unavailable in fetched index.** Search retrieval returned substantive beginnings of all 21 FAQ answers; direct page opens repeatedly failed with redirect loops. Thus only the visible answer text below is usable. The index has one **200-word** budget in aggregate; its mirror/basic-system index does not grant another allowance. [FAQ index](https://markforster.squarespace.com/final-version-faqs/).

- After handling an interruption, return to the same place in the list. [S4](https://markforster.squarespace.com/final-version-faqs/)
- New tasks ordinarily join the end. The urgent-work FAQ distinguishes tasks that can wait until the chain ends from those that cannot. Its full instruction after that distinction was truncated; use S1 for the dotting rule. [S4](https://markforster.squarespace.com/final-version-faqs/)
- No standard chain length is prescribed. The author recommends deleting irrelevant or outdated tasks; FV has no automatic dismissal mechanism of the sort found in earlier systems. [S4](https://markforster.squarespace.com/final-version-faqs/)
- Separate location lists are the standard advice: home/office rather than personal/work. Fixed-time appointments belong outside this discretionary-time selection mechanism. [S4](https://markforster.squarespace.com/final-version-faqs/)
- The author warns that changing the question from doing something *before* another task to wanting it *more* is a common FV mistake. He also says an irrelevant selection may be reprioritized; the rest of that answer was truncated. [S4](https://markforster.squarespace.com/final-version-faqs/)

**S5 — FAQ: Does it matter how often I go through the list? Updated May 13, 2012, 13:11 by Mark Forster.** His guidance is at least three passes on an ordinary day, avoiding oversized selections and using short work sessions. This is practical guidance, not a fixed chain-length rule. Web allowance 200 words. [Dated FAQ](https://markforster.squarespace.com/final-version-faqs/basic-system/does-it-matter-how-often-i-go-through-the-list.html).

**S6 — FAQ: How long should I stick to this before deciding whether it is working for me? Updated May 13, 2014, 18:07 by Mark Forster.** The author recommends checking rule adherence, overload and fatigue before abandoning FV. This supports keeping documented rules separate from adaptations. Web allowance 200 words. [Dated FAQ](https://markforster.squarespace.com/final-version-faqs/basic-system/how-long-should-i-stick-to-this-before-deciding-whether-it-i.html).

### Inferences
- An interruption by itself does not establish that the stored chain is stale; the user can resume. [S4](https://markforster.squarespace.com/final-version-faqs/)
- App documentation should call daily restart an optional product behavior unless a separate primary rule is found. No mandatory daily reset was found in these sources.
- Product terminology must distinguish four operations: continue the saved selection; discard selection marks and choose again; rewrite task entries; erase stored task data. These are different state changes, so an app control called “Reset” cannot be assumed equivalent to Forster's restart wording. This is an implementation analysis, not an additional author rule.

### Gaps
- Could not retrieve full individual FAQs on urgent additions, interruptions, chain editing, exact question wording, or unfinished work because the live Squarespace site loops redirects and the search index mostly exposes answer beginnings.
- Do not attribute the FAQ index's truncated continuation to Forster by guessing its ending.
- Neither an automatic next-day restart nor destructive deletion of the whole list was established. The notes do not claim that the author requires daily dot clearing or daily rewriting. His terminology concerns a chain's relevance; local app Reset semantics require code evidence from the other researcher.

## How can the original be distinguished from later versions and misleading material?

### Takeaway
Use the March 2012 newsletter as the original rule set. Later author changes are valuable context but must retain their own version labels.

### Cited Findings
**S7 — FVP repost, November 16, 2021, 21:39; it labels the original FVP publication May 21, 2015, 11:58.** Forster explicitly presents FVP as amended FV instructions with a changed algorithm and question. It uses wanting a task *more* as its question. Source was retrieved through indexed author home-page content; the direct article failed to open. Web allowance 200 words (same article on homepage and permalink is one allowance). [FVP repost](https://markforster.squarespace.com/blog/2021/11/16/the-final-version-perfected-fvp-instructions-reposted.html).

**S8 — Change to Fast FVP, January 6, 2018, including update at 23:07.** Forster's changed Fast FVP rules permit choosing between the previous dotted task and adding later dots after a worked task. His afternote explicitly says FV, FVP and Simple Scanning can be simulated within those rules. This flexibility does not retroactively redefine original FV. Web allowance 200 words. [Fast FVP change](https://markforster.squarespace.com/blog/2018/1/6/change-to-fast-fvp.html).

**S9 — The Final Version — first look, February 7, 2012, 13:09.** This was a pre-release photo discussion. Many comments are readers' guesses. Forster warned on February 9 that the system had changed considerably from early drafts. Do not treat guessed procedures in these comments as released rules. Web allowance 200 words. [Pre-release discussion](https://markforster.squarespace.com/blog/2012/2/7/the-final-version-first-look.html).

### Inferences
- Beware search summaries which concatenate comments by different authors. A discussion hosted by Forster is not automatically a statement by Forster.

### Gaps
- The 2018 forum page “Summarizing differences between FV, FVP, FFVP — correct?” surfaced a useful summary, but the returned excerpt did not identify its answer's author/date. It was **not used as primary evidence**. URL: https://markforster.squarespace.com/fv-forum/post/2718577.
- FVP's precise rescan location should be established by the researcher assigned later variants; S7's retrieved excerpt in this run did not expose the whole execution loop.
- No local code was inspected or modified in this subtask.
