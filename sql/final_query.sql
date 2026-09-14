-- Final query: target_base for merchant 501, October 2026, Diwali campaigns
-- Expected result: 22
--
-- Short version of the rule (full reasoning in sql/reconciliation/):
--   A campaign only counts if it's approved AND fully processed.
--   Campaigns are grouped into "families" by walking parent_id - a
--   family is a campaign plus every retry chained off it, however
--   deep that goes.
--     - If a family has more than one campaign (an actual retry
--       chain), count distinct customers once each.
--     - If a family is just one standalone campaign, count every
--       row - a repeat customer there is two real, separate sends.

WITH RECURSIVE

-- Walk parent_id upward so every campaign knows which "family" it
-- belongs to. A campaign with no parent starts as its own root; a
-- campaign whose parent is already placed inherits that parent's root.
-- This is what lets a 3-level chain like 9001 -> 9002 -> 9003 all
-- resolve back to 9001, not just one hop.
root_of(id, root_id) AS (
    SELECT id, id
    FROM   campaign
    WHERE  parent_id IS NULL
  UNION ALL
    SELECT c.id, r.root_id
    FROM   campaign c
    JOIN   root_of  r ON c.parent_id = r.id
),

-- How many campaigns are in each family? 1 = standalone, more than
-- that = an actual retry chain. This decides which counting rule
-- applies below. I'm computing this over every campaign, not just the
-- eligible ones, since being part of a chain is a fact about
-- parent_id, not about approval status - though I checked, and doing
-- it the other way around doesn't change the answer here either.
chain_size AS (
    SELECT root_id, COUNT(*) AS campaigns_in_chain
    FROM   root_of
    GROUP  BY root_id
),

-- The actual sends in scope, each one tagged with which family it
-- belongs to. This is also where the eligibility filter lives -
-- communication_log can have rows for a campaign that hasn't cleared
-- approval yet (the send pipeline doesn't wait around for that), so
-- those need to be dropped here.
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

-- Apply the actual rule: distinct customers for a chain, plain row
-- count for a standalone campaign. One CASE statement, one family per
-- row.
per_communication AS (
    SELECT root_id,
           CASE WHEN campaigns_in_chain > 1
                THEN COUNT(DISTINCT customer_id)  -- chain: collapse repeat attempts
                ELSE COUNT(log_id)                -- standalone: every row is its own send
           END AS qualifying_sends
    FROM   eligible_sends
    GROUP  BY root_id, campaigns_in_chain
)

SELECT SUM(qualifying_sends) AS target_base
FROM   per_communication;
