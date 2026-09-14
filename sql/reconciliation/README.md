# Reconciliation, one query at a time

Each file here is one query I ran while figuring out how Finance's `target_base` of 22
was actually calculated. Run any of them directly:

```bash
sqlite3 -header -column ../../data/comm_log.db < step1_naive_count.sql
```

I split it this way instead of one long script because the point of this assignment
isn't the final number, it's the path to it - so each step gets its own file and its own
reasoning, in the order I actually did them.

## The real bridge

| File | What it checks | Result |
|---|---|---|
| [`step1_naive_count.sql`](step1_naive_count.sql) | Just count every send in scope | **30** |
| [`step2_eligibility_filter.sql`](step2_eligibility_filter.sql) | Drop the one campaign that's still pending approval | **26** |
| [`rejected_global_distinct.sql`](rejected_global_distinct.sql) | *(wrong turn)* count unique customers, globally | 21 |
| [`step3_final_dedupe.sql`](step3_final_dedupe.sql) | Dedupe only inside retry chains, not standalone campaigns | **22** ✅ |

## Other things I tried and ruled out

These all came after I already had 22 - I wanted to check whether some simpler rule
would have gotten me there too, since if it does, matching the number alone doesn't
prove much.

| File | Idea | Result | Why it's not the answer |
|---|---|---|---|
| [`alt_per_campaign_distinct.sql`](alt_per_campaign_distinct.sql) | Dedupe per campaign instead of per chain | 25 | Doesn't collapse a multi-step retry chain at all |
| [`alt_root_only.sql`](alt_root_only.sql) | Ignore retries, only count the original campaign | 22 | Ties by coincidence - breaks in `../counterfactuals.sql` |
| [`alt_delivered_only.sql`](alt_delivered_only.sql) | Only count messages that actually delivered | 22 | Ties by coincidence - breaks in `../counterfactuals.sql` |

The full writeup with evidence for each is in
[`../../analysis/reconciliation_bridge.md`](../../analysis/reconciliation_bridge.md).
