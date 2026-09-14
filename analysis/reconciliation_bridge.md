# Reconciliation bridge

merchant 501, October 2026, Diwali campaigns. Naive count says 30. Finance says 22.

Every number here comes straight out of the files in `sql/reconciliation/` - I re-ran
each one before writing this so nothing below is typed from memory.

## The actual bridge

| Step | Description | Result | Reason |
|---|---|---|---|
| 0 | Naive count | 30 | Starting point - one `communication_log` row = one send |
| 1 | Drop campaigns not cleared for reporting | 26 | Campaign 9004 is still `approval_awaiting`; its 4 rows exist but aren't signed off yet |
| 2 | *(wrong turn)* Dedupe customers globally | 21 | Tried this first, one short - see below |
| final | Dedupe only inside retry chains | **22** | Collapses C2 / C3 / D1's repeat attempts, leaves standalone repeats (C20) alone |

**Why step 2 is in here even though it's wrong:** landing on 21 instead of 22 is what
actually pointed me at the bug. Digging into which customer got dropped led me to C20,
who has two delivered messages under the same standalone campaign, ten days apart -
not a retry, just two real sends. That's the exact evidence for the rule I used in the
final step: only collapse repeats that happen *within* a retry chain (a campaign
retried through `parent_id`), never a repeat under one standalone campaign.

Composition of the final 22: chain 9001→9002→9003 contributes 10 (distinct customers),
standalone 9101 contributes 7 (every row counts, including C20 twice), chain
9201→9202 contributes 5. `10 + 7 + 5 = 22`.

## Other approaches I tested and rejected

I kept finding other ways to slice this that also land on 22, which made me nervous -
if three different rules give the same number, getting 22 doesn't prove anything by
itself. So for the two that tied, I stress-tested them in `sql/counterfactuals.sql`
instead of just accepting the coincidence.

| Approach | Result | Why I didn't use it |
|---|---|---|
| Dedupe per campaign instead of per chain | 25 | Doesn't collapse C3's chain at all - 9001/9002/9003 are 3 different campaign ids |
| Ignore retries, only count the original campaign | 22 | Ties by coincidence - every retried customer here happens to also have a row at the root. Breaks (23 vs 22) the moment a customer is only ever reached through a retry |
| Only count delivered messages | 22 | Ties by coincidence - no eligible customer here has zero deliveries. Breaks (22 vs 21) the moment a retried customer never once succeeds |

Query files for all of this are in [`sql/reconciliation/`](../sql/reconciliation/), with
the same reasoning written directly into each `.sql` file's comments.

## What surprised me

Honestly, the biggest surprise was that getting to 22 wasn't the hard part - three
completely different ways of counting all get there. What's actually hard is telling
which one is *correct*, and the only way I found to do that was to break each one on
purpose and see if it still agreed with the data dictionary's definition. C20 is the
single customer that makes or breaks this whole exercise - if you dedupe them away,
you're one short; if you don't understand why they shouldn't be deduped, you can't
explain why the "obvious" fix (global distinct) is wrong.
