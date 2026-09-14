-- Stress-testing the two answers that also equal 22
--
-- reconciliation/alt_root_only.sql and reconciliation/alt_delivered_only.sql
-- both land on 22, same as my actual method in
-- reconciliation/step3_final_dedupe.sql. That bugged me - if three
-- different ways of counting all give the same number, matching 22
-- doesn't actually prove any of them is right.
--
-- So instead of just trusting the tie, I made one small, realistic
-- change to a COPY of the data for each alternative and checked whether
-- it still agreed with my method. If it's the right rule, changing one
-- unrelated thing shouldn't make it disagree.
--
-- RUN THIS ONLY ON A COPY, NEVER data/comm_log.db ITSELF:
--   cp data/comm_log.db /tmp/counterfactual.db
--   sqlite3 /tmp/counterfactual.db < sql/counterfactuals.sql
--
-- What I expect to see:
--   Test 1 (root-only):      my_method=23   root_only=22   -> they disagree
--   Test 2 (delivered-only): my_method=22   delivered_only=21  -> they disagree

-- ---------------------------------------------------------------------
-- Test 1: a customer who was ONLY ever reached through a retry
--
-- reconciliation/alt_root_only.sql ties at 22 because, in the real
-- data, every retried customer also happens to have a row under the
-- original campaign. That's just how this dataset turned out - nothing
-- says it has to be true. So I added one made-up customer whose only
-- attempt is under a RETRY campaign (9003), never the original (9001).
-- A believable version of this in real life: someone's number bounced
-- on the first send, got fixed, and was added straight into the retry
-- batch instead of the original one.
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
           FROM eligible GROUP BY root_id, n)) AS my_method,
    (SELECT SUM(n) FROM (
        SELECT c.id, COUNT(*) AS n
        FROM   communication_log l
        JOIN   campaign c ON c.id = l.communication_id
        WHERE  c.parent_id IS NULL
          AND  c.creation_status IN ('approved','aborted','resumed','stopped')
          AND  c.processing_status = 'processed'
        GROUP BY c.id)) AS root_only;
-- I get 23 vs 22. My method correctly picks up the new customer;
-- root-only never even looks at the row it's sitting in, so it stays
-- at 22 and quietly misses a real person. That's the proof it was
-- never actually a safe rule, just a lucky coincidence on this data.

DELETE FROM communication_log WHERE id = 9901;

-- ---------------------------------------------------------------------
-- Test 2: a retried customer who never actually succeeds
--
-- reconciliation/alt_delivered_only.sql ties at 22 because every
-- eligible customer in the real data eventually got at least one
-- delivered message. I flipped C3's one successful attempt (the row
-- under campaign 9003) back to a failure, so C3 now has three failed
-- attempts and zero deliveries.
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
           FROM eligible GROUP BY root_id, n)) AS my_method,
    (SELECT COUNT(*) FROM eligible WHERE delivery_status = 900) AS delivered_only;
-- I get 22 vs 21. My method still counts C3 as targeted no matter how
-- the attempts turned out - they were part of the 9001 chain either
-- way. Delivered-only needs at least one success per customer, so the
-- moment C3 has none, they vanish from that count entirely. That's the
-- gap between "counts who Finance targeted" and "counts who actually
-- got the message" - two different metrics that just happen to agree
-- on the real data.

UPDATE communication_log SET delivery_status = 900 WHERE id = 6;  -- put it back, this is a shared copy
