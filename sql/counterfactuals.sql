-- =====================================================================
-- Counterfactual tests. These prove that "root-only" and "delivered-
-- only" (both = 22 on the supplied data) are coincidences, not correct
-- rules -- by showing a single-row change makes them diverge from the
-- retry-family-aware method.
--
-- RUN THIS ONLY AGAINST A DISPOSABLE COPY OF THE DATABASE, NEVER
-- data/comm_log.db ITSELF:
--
--   cp data/comm_log.db /tmp/counterfactual.db
--   sqlite3 /tmp/counterfactual.db < sql/counterfactuals.sql
--
-- Expected output (two SELECTs per counterfactual, run in order):
--   Counterfactual 1 (root-only):      final_method=23   root_only=22
--   Counterfactual 2 (delivered-only): final_method=22   delivered_only=21
-- =====================================================================

-- ---------------------------------------------------------------------
-- COUNTERFACTUAL 1 -- a customer reached only via a retry child.
-- Simulates a retry audience being expanded to include someone who was
-- never part of the original send (plausible in practice: a bounced
-- contact gets fixed and added directly to the retry list).
-- ---------------------------------------------------------------------
INSERT INTO communication_log
VALUES (9901, 501, 9003, 'CF_ROOT_ONLY', '2', 900,
        '2026-10-05 11:00:00', '2026-10-05 11:00:00', 1, 'sms');

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
SELECT
    (SELECT SUM(CASE WHEN n > 1 THEN dc ELSE rows_ END)
     FROM (SELECT root_id, n, COUNT(DISTINCT customer_id) AS dc, COUNT(log_id) AS rows_
           FROM eligible GROUP BY root_id, n)) AS final_method,
    (SELECT SUM(n) FROM (
        SELECT c.id, COUNT(*) AS n
        FROM   communication_log l
        JOIN   campaign c ON c.id = l.communication_id
        WHERE  c.parent_id IS NULL
          AND  c.creation_status IN ('approved','aborted','resumed','stopped')
          AND  c.processing_status = 'processed'
        GROUP BY c.id)) AS root_only;
-- Expect: final_method = 23 (gains CF_ROOT_ONLY), root_only = 22 (misses them)

DELETE FROM communication_log WHERE id = 9901;

-- ---------------------------------------------------------------------
-- COUNTERFACTUAL 2 -- a retried customer who never succeeds.
-- Simulates C3's chain (9001 -> 9002 -> 9003) ending in failure instead
-- of eventual delivery.
-- ---------------------------------------------------------------------
UPDATE communication_log SET delivery_status = 1100 WHERE id = 6;  -- C3's delivered row under 9003

WITH RECURSIVE root_of(id, root_id) AS (
        SELECT id, id FROM campaign WHERE parent_id IS NULL
      UNION ALL
        SELECT c.id, r.root_id FROM campaign c JOIN root_of r ON c.parent_id = r.id),
chain_size AS (SELECT root_id, COUNT(*) AS n FROM root_of GROUP BY root_id),
eligible AS (
    SELECT r.root_id, s.n, l.customer_id, l.id AS log_id, l.delivery_status
    FROM   communication_log l
    JOIN   campaign   c ON c.id = l.communication_id
    JOIN   root_of    r ON r.id = c.id
    JOIN   chain_size s ON s.root_id = r.root_id
    WHERE  c.creation_status IN ('approved','aborted','resumed','stopped')
      AND  c.processing_status = 'processed')
SELECT
    (SELECT SUM(CASE WHEN n > 1 THEN dc ELSE rows_ END)
     FROM (SELECT root_id, n, COUNT(DISTINCT customer_id) AS dc, COUNT(log_id) AS rows_
           FROM eligible GROUP BY root_id, n)) AS final_method,
    (SELECT COUNT(*) FROM eligible WHERE delivery_status = 900) AS delivered_only;
-- Expect: final_method = 22 (C3 still targeted, chain still resolves to 10),
--         delivered_only = 21 (C3 now has zero delivered rows, drops out)

UPDATE communication_log SET delivery_status = 900 WHERE id = 6;  -- restore, since this is a shared copy
