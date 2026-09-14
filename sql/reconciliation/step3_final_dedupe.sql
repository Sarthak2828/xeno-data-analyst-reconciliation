-- Step 3: dedupe inside a retry chain, but not inside a standalone campaign
--
-- The data dictionary says target_base is counted per "underlying
-- communication" - a campaign plus every retry chained off it through
-- parent_id. So the fix from rejected_global_distinct.sql isn't "never
-- dedupe" or "always dedupe" - it's "dedupe only within a chain."
--
-- To find each campaign's chain I walk parent_id upward with a
-- recursive CTE (root_of), since a chain can be more than one level
-- deep - 9001 -> 9002 -> 9003 is three levels here. Then I count how
-- many campaigns are in each family (chain_size): 1 means standalone,
-- more than 1 means it's an actual retry chain.
--
-- Same core logic as sql/final_query.sql, written out here as its own
-- step so the bridge is easy to follow one query at a time.
--
-- Result: 22

WITH RECURSIVE root_of(id, root_id) AS (
    SELECT id, id FROM campaign WHERE parent_id IS NULL
  UNION ALL
    SELECT c.id, r.root_id FROM campaign c JOIN root_of r ON c.parent_id = r.id
),
chain_size AS (
    SELECT root_id, COUNT(*) AS n FROM root_of GROUP BY root_id
),
eligible AS (
    SELECT r.root_id, s.n, l.customer_id, l.id AS log_id
    FROM   communication_log l
    JOIN   campaign   c ON c.id = l.communication_id
    JOIN   root_of    r ON r.id = c.id
    JOIN   chain_size s ON s.root_id = r.root_id
    WHERE  c.creation_status IN ('approved', 'aborted', 'resumed', 'stopped')
      AND  c.processing_status = 'processed'
)
SELECT SUM(CASE WHEN n > 1 THEN dc ELSE rows_ END) AS final_dedupe_result
FROM  (SELECT root_id, n, COUNT(DISTINCT customer_id) AS dc, COUNT(log_id) AS rows_
       FROM eligible GROUP BY root_id, n);
