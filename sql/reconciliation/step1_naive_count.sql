-- Step 1: the naive count
--
-- Before touching any business logic, this is the query I'd write if
-- someone just handed me this dataset and asked "how many sends were
-- there?" One row in communication_log = one send, filtered down to
-- the scope the assignment actually asks about.
--
-- I also checked the extra filters below (channel, exact merchant match
-- on the campaign side) separately and they don't remove anything -
-- every row already satisfies them, so I'm not counting that as a real
-- step, just noting I checked.
--
-- Result: 30

SELECT COUNT(*) AS naive_count
FROM   communication_log l
JOIN   campaign c ON c.id = l.communication_id
WHERE  l.merchant_id = 501
  AND  l.communication_type = '2'
  AND  l.sent_time >= '2026-10-01' AND l.sent_time < '2026-11-01'
  AND  c.name LIKE '%Diwali%';
