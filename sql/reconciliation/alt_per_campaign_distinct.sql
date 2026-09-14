-- Alternative I considered: dedupe per campaign, not per chain
--
-- A slightly more careful version of the rejected global-distinct
-- attempt - instead of one global distinct count, dedupe customer_id
-- within EACH campaign separately. Seemed like it might avoid the C20
-- problem since it wouldn't merge things across different campaigns.
--
-- Doesn't work either. Customer C3 shows up under 9001, 9002, and 9003
-- - three different campaign ids - so this treats all three as
-- separate, distinct (campaign, customer) pairs and never collapses
-- the chain at all. It just doesn't implement the "retry chain = one
-- underlying communication" idea from the data dictionary.
--
-- Result: 25 (rejected)

SELECT COUNT(*) AS per_campaign_distinct_pairs
FROM   (SELECT DISTINCT l.communication_id, l.customer_id
        FROM   communication_log l
        JOIN   campaign c ON c.id = l.communication_id
        WHERE  c.creation_status IN ('approved', 'aborted', 'resumed', 'stopped')
          AND  c.processing_status = 'processed');
