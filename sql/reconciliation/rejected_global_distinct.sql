-- Rejected attempt: just count unique customers
--
-- My first instinct after step 2 (26) was that a few customers show up
-- more than once in the log, so I should just count distinct
-- customer_id and be done with it. That felt like the obvious fix.
--
-- It gave me 21, not 22 - one short.
--
-- Digging into who got dropped, it's customer C20 under campaign 9101.
-- C20 has TWO delivered messages, ten days apart, under the exact same
-- campaign. That's not a retry (a retry always creates a new campaign
-- row per the data dictionary) - it's just two separate, real sends to
-- the same person. Deduping globally quietly deleted one of them.
--
-- So this query is wrong, but it's the one that pointed me at C20,
-- which is what led to the actual rule in step3_final_dedupe.sql:
-- only collapse repeats that happen INSIDE a retry chain.
--
-- Result: 21 (rejected)

SELECT COUNT(DISTINCT l.customer_id) AS global_distinct_customers
FROM   communication_log l
JOIN   campaign c ON c.id = l.communication_id
WHERE  c.creation_status IN ('approved', 'aborted', 'resumed', 'stopped')
  AND  c.processing_status = 'processed';
