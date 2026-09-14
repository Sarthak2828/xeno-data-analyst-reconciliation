-- Alternative I considered: only count messages that actually delivered
--
-- delivery_status = 900 means delivered, 1100 means failed. "Qualifying
-- send" sounds like it could mean "a send that actually succeeded," so
-- I tried filtering to delivered rows only, on top of the eligibility
-- filter from step 2.
--
-- Also lands on 22, also a coincidence. Among the 26 eligible rows, no
-- customer is ever left with zero delivered messages, and the one
-- customer with two delivered rows (C20, under the standalone campaign)
-- would count as 2 either way. So this ties the right number here, but
-- not because it's the right rule.
--
-- Two reasons I didn't keep it: the data dictionary never mentions
-- delivery status when it defines target_base, and the failed rows
-- still cost credit_used = 1 each, meaning they're real billed attempts
-- and not something the metric obviously wants to ignore. I broke this
-- one in sql/counterfactuals.sql too - if a retried customer never
-- once succeeds, this drops to 21 while the real method stays at 22.
--
-- Result: 22 (ties the right answer, still rejected)

SELECT COUNT(*) AS delivered_only_count
FROM   communication_log l
JOIN   campaign c ON c.id = l.communication_id
WHERE  c.creation_status IN ('approved', 'aborted', 'resumed', 'stopped')
  AND  c.processing_status = 'processed'
  AND  l.delivery_status = 900;
