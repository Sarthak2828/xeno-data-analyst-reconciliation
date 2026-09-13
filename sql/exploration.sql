-- =====================================================================
-- Phase 1 profiling. These are the queries actually run to understand
-- the data before any reconciliation was attempted.
--   sqlite3 -header -column data/comm_log.db < sql/exploration.sql
-- =====================================================================

-- Row counts.
SELECT (SELECT COUNT(*) FROM campaign)          AS campaign_rows,
       (SELECT COUNT(*) FROM communication_log) AS comm_log_rows;

-- Full campaign table (only 7 rows - small enough to read directly).
SELECT id, merchant_id, COALESCE(CAST(parent_id AS TEXT),'NULL') AS parent_id,
       name, creation_status, processing_status
FROM   campaign ORDER BY id;

-- Nulls / distinct values per column.
SELECT 'campaign' AS tbl,'parent_id' AS col,COUNT(*) AS n,COUNT(parent_id) AS non_null,
       COUNT(DISTINCT parent_id) AS distinct_vals FROM campaign
UNION ALL SELECT 'comm_log','customer_id',COUNT(*),COUNT(customer_id),COUNT(DISTINCT customer_id) FROM communication_log
UNION ALL SELECT 'comm_log','communication_id',COUNT(*),COUNT(communication_id),COUNT(DISTINCT communication_id) FROM communication_log
UNION ALL SELECT 'comm_log','delivery_status',COUNT(*),COUNT(delivery_status),COUNT(DISTINCT delivery_status) FROM communication_log;

-- Categorical values.
SELECT creation_status, processing_status, COUNT(*) AS n FROM campaign GROUP BY 1,2;
SELECT delivery_status, channel, communication_type, credit_used, COUNT(*) AS n
FROM   communication_log GROUP BY 1,2,3,4;

-- Date range and boundary safety.
SELECT MIN(sent_time) AS min_sent, MAX(sent_time) AS max_sent,
       SUM(sent_time <  '2026-10-01') AS before_oct,
       SUM(sent_time >= '2026-11-01') AS after_oct,
       SUM(sent_time <> scheduled_time) AS sent_ne_scheduled
FROM   communication_log;

-- Referential integrity: orphans, dangling parents, merchant mismatch.
SELECT (SELECT COUNT(*) FROM communication_log l LEFT JOIN campaign c ON c.id=l.communication_id WHERE c.id IS NULL) AS orphan_log_rows,
       (SELECT COUNT(*) FROM campaign c WHERE c.parent_id IS NOT NULL AND c.parent_id NOT IN (SELECT id FROM campaign)) AS dangling_parents,
       (SELECT COUNT(*) FROM communication_log l JOIN campaign c ON c.id=l.communication_id WHERE c.merchant_id<>l.merchant_id) AS merchant_mismatch;

-- Exact duplicate business rows (ignoring surrogate id): none expected.
SELECT merchant_id, communication_id, customer_id, delivery_status, sent_time, COUNT(*) AS n
FROM   communication_log GROUP BY 1,2,3,4,5 HAVING COUNT(*) > 1;

-- Same customer twice under the SAME campaign (the standalone repeat).
SELECT communication_id, customer_id, COUNT(*) AS n,
       GROUP_CONCAT(id) AS row_ids, GROUP_CONCAT(delivery_status) AS statuses,
       GROUP_CONCAT(sent_time) AS times
FROM   communication_log GROUP BY 1,2 HAVING COUNT(*) > 1;

-- Same customer across MULTIPLE campaigns (the retry-chain repeats).
SELECT customer_id, COUNT(DISTINCT communication_id) AS n_campaigns,
       GROUP_CONCAT(DISTINCT communication_id) AS campaigns
FROM   communication_log GROUP BY 1 HAVING COUNT(DISTINCT communication_id) > 1;

-- Campaign graph shape: parent, child count, standalone vs in-chain.
SELECT c.id, COALESCE(CAST(c.parent_id AS TEXT),'-') AS parent,
       (SELECT COUNT(*) FROM campaign k WHERE k.parent_id=c.id) AS n_children,
       CASE WHEN c.parent_id IS NULL
                 AND NOT EXISTS(SELECT 1 FROM campaign k WHERE k.parent_id=c.id)
            THEN 'STANDALONE' ELSE 'IN_CHAIN' END AS shape,
       c.creation_status, c.name
FROM   campaign c ORDER BY c.id;

-- Cardinality check: campaign -> communication_log is 1:many, so joining
-- on the FK cannot multiply log rows.
SELECT (SELECT COUNT(*) FROM communication_log) AS before_join,
       (SELECT COUNT(*) FROM communication_log l JOIN campaign c ON c.id=l.communication_id) AS after_join;
