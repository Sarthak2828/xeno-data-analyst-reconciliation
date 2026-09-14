-- Step 2: drop campaigns that aren't actually cleared for reporting
--
-- Looking at the campaign table, one row (9004) is stuck in
-- 'approval_awaiting' even though the send pipeline already ran and
-- attached 4 rows to it in communication_log. The data dictionary is
-- pretty explicit that a campaign only counts once BOTH the approval
-- step and the processing step are done, so those 4 rows shouldn't be
-- in the final number even though they're real, delivered messages.
--
-- Result: 26 (down from 30, so -4)

SELECT COUNT(*) AS after_eligibility_filter
FROM   communication_log l
JOIN   campaign c ON c.id = l.communication_id
WHERE  c.creation_status IN ('approved', 'aborted', 'resumed', 'stopped')
  AND  c.processing_status = 'processed';
