-- =====================================================================
-- Finance metric: target_base
-- Scope: merchant_id = 501, October 2026, communication_type = '2'
--        (Campaign), all "Diwali" campaigns.
-- Expected result: 22
--
-- Definition (from README.md, "What reporting considers a qualifying send"):
--   target_base counts qualifying sends per UNDERLYING COMMUNICATION.
--   An underlying communication = a root campaign PLUS every campaign
--   chained off it via campaign.parent_id (retries, at any depth).
--     * Retry chain (>1 campaign in the family): a customer who needed
--       several attempts to finally be delivered counts ONCE.
--     * Standalone campaign (no parent, no children): every send row is
--       its own event, even if the same customer appears twice.
--   Only campaigns whose creation workflow has cleared AND whose send
--   pipeline has finished are eligible for official reporting.
-- =====================================================================

WITH RECURSIVE

-- 1. Resolve every campaign to the ROOT of its retry chain by walking
--    parent_id upwards. Roots seed the recursion; children inherit the
--    root_id of their parent, so A -> B -> C all resolve to A.
root_of(id, root_id) AS (
    SELECT id, id
    FROM   campaign
    WHERE  parent_id IS NULL
  UNION ALL
    SELECT c.id, r.root_id
    FROM   campaign c
    JOIN   root_of  r ON c.parent_id = r.id
),

-- 2. Family size decides the counting rule. Size 1 = standalone
--    communication; size > 1 = retry chain. Shape is a structural
--    property of the campaign graph, so it is measured over ALL
--    campaigns, before the reporting-eligibility filter is applied.
chain_size AS (
    SELECT root_id, COUNT(*) AS campaigns_in_chain
    FROM   root_of
    GROUP  BY root_id
),

-- 3. Send rows in scope, tagged with their underlying communication.
--    Campaign-level eligibility gate is applied here:
--      creation_status must be finalized/live, and
--      processing_status must be 'processed'.
--    (communication_log rows can exist for a campaign that has not yet
--     cleared approval - the send pipeline runs ahead of bookkeeping.)
eligible_sends AS (
    SELECT r.root_id,
           s.campaigns_in_chain,
           l.customer_id,
           l.id AS log_id
    FROM   communication_log l
    JOIN   campaign   c ON c.id      = l.communication_id
    JOIN   root_of    r ON r.id      = c.id
    JOIN   chain_size s ON s.root_id = r.root_id
    WHERE  l.merchant_id        = 501
      AND  l.communication_type = '2'
      AND  l.sent_time         >= '2026-10-01'
      AND  l.sent_time          < '2026-11-01'
      AND  c.name LIKE '%Diwali%'
      AND  c.creation_status IN ('approved', 'aborted', 'resumed', 'stopped')
      AND  c.processing_status = 'processed'
),

-- 4. Apply the per-communication counting rule.
per_communication AS (
    SELECT root_id,
           CASE WHEN campaigns_in_chain > 1
                -- retry chain: collapse repeat attempts at the customer
                THEN COUNT(DISTINCT customer_id)
                -- standalone: every send row is its own event
                ELSE COUNT(log_id)
           END AS qualifying_sends
    FROM   eligible_sends
    GROUP  BY root_id, campaigns_in_chain
)

SELECT SUM(qualifying_sends) AS target_base
FROM   per_communication;
