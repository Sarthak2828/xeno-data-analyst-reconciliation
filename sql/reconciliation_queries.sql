-- =====================================================================
-- Reconciliation bridge, step by step. Each SELECT is the actual query
-- run at that stage of the investigation; the numbers in
-- analysis/reconciliation_bridge.md come from running this file.
--   sqlite3 -header -column data/comm_log.db < sql/reconciliation_queries.sql
-- =====================================================================

-- STEP 0 -- Naive count: every send row in the stated scope.
SELECT 'step 0: naive COUNT(*) of all sends' AS step, COUNT(*) AS result
FROM   communication_log l
JOIN   campaign c ON c.id = l.communication_id
WHERE  l.merchant_id = 501
  AND  l.communication_type = '2'
  AND  l.sent_time >= '2026-10-01' AND l.sent_time < '2026-11-01'
  AND  c.name LIKE '%Diwali%';

-- STEP 1 -- Scope validation. Tightening merchant / type / date / name
-- changes nothing: every row already qualifies. Recorded as a
-- validation, not an adjustment.
SELECT 'step 1: scope filters (no-op, validation)' AS step, COUNT(*) AS result
FROM   communication_log l
JOIN   campaign c ON c.id = l.communication_id
WHERE  l.merchant_id = 501 AND l.communication_type = '2' AND l.channel = 'sms'
  AND  l.sent_time >= '2026-10-01' AND l.sent_time < '2026-11-01'
  AND  c.name LIKE '%Diwali%' AND c.merchant_id = 501;

-- STEP 2 -- Campaign eligibility gate. Campaign 9004 is still
-- 'approval_awaiting', so its 4 send rows must not be reported even
-- though they exist in communication_log.
SELECT 'step 2: drop campaigns not cleared for reporting' AS step, COUNT(*) AS result
FROM   communication_log l
JOIN   campaign c ON c.id = l.communication_id
WHERE  c.creation_status IN ('approved','aborted','resumed','stopped')
  AND  c.processing_status = 'processed';

-- STEP 3a -- FIRST ATTEMPT AT DEDUPE (rejected). Deduplicating
-- customers globally overshoots: it wrongly merges C20's two genuine
-- standalone sends into one. Result 21, not 22 -- this mismatch is what
-- exposed the chain-vs-standalone rule.
SELECT 'step 3a: global COUNT(DISTINCT customer) -- REJECTED' AS step,
       COUNT(DISTINCT l.customer_id) AS result
FROM   communication_log l
JOIN   campaign c ON c.id = l.communication_id
WHERE  c.creation_status IN ('approved','aborted','resumed','stopped')
  AND  c.processing_status = 'processed';

-- STEP 3b -- CORRECT DEDUPE. Collapse repeat attempts only WITHIN a
-- retry chain; standalone campaigns keep every send row.
WITH RECURSIVE root_of(id, root_id) AS (
        SELECT id, id FROM campaign WHERE parent_id IS NULL
      UNION ALL
        SELECT c.id, r.root_id FROM campaign c JOIN root_of r ON c.parent_id = r.id),
chain_size AS (SELECT root_id, COUNT(*) AS n FROM root_of GROUP BY root_id),
eligible AS (
    SELECT r.root_id, s.n, l.customer_id, l.id AS log_id
    FROM   communication_log l
    JOIN   campaign   c ON c.id = l.communication_id
    JOIN   root_of    r ON r.id = c.id
    JOIN   chain_size s ON s.root_id = r.root_id
    WHERE  c.creation_status IN ('approved','aborted','resumed','stopped')
      AND  c.processing_status = 'processed')
SELECT 'step 3b: dedupe within retry chains only' AS step,
       SUM(CASE WHEN n > 1 THEN dc ELSE rows_ END) AS result
FROM  (SELECT root_id, n, COUNT(DISTINCT customer_id) AS dc, COUNT(log_id) AS rows_
       FROM eligible GROUP BY root_id, n);

-- =====================================================================
-- Two further rejected alternatives, kept here for completeness. Both
-- also land on numbers other than 22, or land on 22 for reasons that
-- don't hold up -- see analysis/reconciliation_bridge.md for the full
-- argument, including the counterfactuals that disprove the two that
-- DO land on 22 (root-only, delivered-only).
-- =====================================================================

-- ALT D -- distinct (campaign, customer) pairs. Under-collapses retry
-- chains: C3 still counts 3 times because 9001/9002/9003 are 3
-- different campaign ids, even though they're one underlying
-- communication. Result: 25.
SELECT 'alt D: distinct (campaign, customer) pairs -- REJECTED' AS step,
       COUNT(*) AS result
FROM   (SELECT DISTINCT l.communication_id, l.customer_id
        FROM   communication_log l
        JOIN   campaign c ON c.id = l.communication_id
        WHERE  c.creation_status IN ('approved','aborted','resumed','stopped')
          AND  c.processing_status = 'processed');

-- ALT E -- root-only: ignore every retry-child row entirely, COUNT(*)
-- of rows sent under just the root campaign. Numerically ties at 22 on
-- THIS dataset (every retried customer also has a row at the root) but
-- contradicts the data dictionary, which requires looking at "a
-- campaign plus every retry chained off it". Disproved by the C99
-- counterfactual in the bridge doc (a customer only ever attempted in
-- a retry child is invisible to this method).
SELECT 'alt E: root-only COUNT(*), retry rows discarded -- REJECTED' AS step,
       SUM(n) AS result
FROM   (SELECT c.id, COUNT(*) AS n
        FROM   communication_log l
        JOIN   campaign c ON c.id = l.communication_id
        WHERE  c.parent_id IS NULL
          AND  c.creation_status IN ('approved','aborted','resumed','stopped')
          AND  c.processing_status = 'processed'
        GROUP  BY c.id);

-- ALT F -- delivered-only: keep only delivery_status = 900. Ties at 22
-- on THIS dataset (0 eligible customers are never delivered, and the
-- one eligible customer with 2 delivered rows -- C20 -- is standalone,
-- where both rows count correctly anyway). Not required or forbidden
-- by the data dictionary; documented as an ambiguity, not disproven by
-- the docs -- disproved instead by the C3-never-succeeds counterfactual
-- in the bridge doc.
SELECT 'alt F: delivered-only (900), eligible -- REJECTED AS MECHANISM' AS step,
       COUNT(*) AS result
FROM   communication_log l
JOIN   campaign c ON c.id = l.communication_id
WHERE  c.creation_status IN ('approved','aborted','resumed','stopped')
  AND  c.processing_status = 'processed'
  AND  l.delivery_status = 900;
