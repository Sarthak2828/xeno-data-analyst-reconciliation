-- Alternative I considered: only count the root campaign, ignore retries
--
-- Simplest possible way to "not double count retries": don't look at
-- the retry rows at all, just count whatever was sent under the
-- original campaign (parent_id IS NULL).
--
-- This actually lands on 22 as well, but only by coincidence. On this
-- dataset, every customer who got retried already has a row under the
-- root campaign too (that's the failed attempt that triggered the
-- retry in the first place), so ignoring the retries doesn't lose
-- anyone here. But the data dictionary specifically defines the metric
-- over "a campaign plus every retry chained off it" - so this approach
-- is throwing away exactly the data the definition says to include.
--
-- I proved it breaks in sql/counterfactuals.sql: adding one customer
-- who is ONLY ever reached through a retry campaign (never the root)
-- makes this query miss them completely, while step3_final_dedupe.sql
-- correctly picks them up.
--
-- Result: 22 (ties the right answer, still rejected)

SELECT SUM(n) AS root_only_count
FROM   (SELECT c.id, COUNT(*) AS n
        FROM   communication_log l
        JOIN   campaign c ON c.id = l.communication_id
        WHERE  c.parent_id IS NULL
          AND  c.creation_status IN ('approved', 'aborted', 'resumed', 'stopped')
          AND  c.processing_status = 'processed'
        GROUP  BY c.id);
