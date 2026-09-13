# Reconciliation Bridge — `target_base`, merchant 501, October 2026, Diwali campaigns

Every number below is the output of an executed query against `data/comm_log.db`
(see `sql/reconciliation_queries.sql`, `sql/exploration.sql`, `sql/final_query.sql`). None is
asserted from memory or worked backward from 22.

**Scope held constant across every step:** `merchant_id = 501`, `communication_type =
'2'`, `sent_time` in `['2026-10-01', '2026-11-01')`, campaign `name LIKE '%Diwali%'`.
No step below compares populations that differ in scope.

---

## The bridge

| Step | Description | Result | Adjustment | Reason |
|---|---|---|---|---|
| 1 | Naive/scoped communication count | **30** | — | Starting point: one `communication_log` row = one send, in the stated scope. |
| 2 | Remove campaign-ineligible records | **26** | **−4** | Campaign 9004 is `approval_awaiting`; the data dictionary states a campaign counts toward reporting only once both `creation_status` is finalized and `processing_status = 'processed'`. Its 4 rows (C11–C14) exist in the log but are not signed off. |
| 3 | Apply retry-family deduplication | **22** | **−4** | The data dictionary defines `target_base` per *underlying communication* — a root campaign plus every campaign chained off it via `parent_id`. Within a retry chain, several attempts to reach one customer are one qualifying send; standalone campaigns are unaffected. |

**30 − 4 − 4 = 22.**

### How the final 22 is composed

| Underlying communication | Shape | Eligible rows | Distinct customers | Contributes |
|---|---|---|---|---|
| 9001 → 9002 → 9003 | Retry chain | 13 | 10 | **10** |
| 9101 | Standalone | 7 | 6 | **7** |
| 9201 → 9202 | Retry chain | 6 | 5 | **5** |
| | | | **Total** | **22** |

---

## Validations (checked, correctly changed nothing — not counted as bridge steps)

| Check | Finding |
|---|---|
| Date boundary | All 30 real sends fall 2026-10-03 → 2026-10-20; a synthetic robustness check (throwaway copy) confirms a row at `2026-10-31 23:59:59` is included and one at `2026-11-01 00:00:00` is excluded — the half-open interval is correctly implemented. |
| Merchant / type / channel | 100% of rows are `merchant_id=501`, `communication_type='2'`, `channel='sms'`. |
| "Diwali campaigns" filter | All 7 campaigns contain "Diwali" — a no-op on this dataset, kept because it is part of the metric's stated scope. |
| Referential integrity | 0 orphan log rows, 0 dangling `parent_id`, 0 merchant mismatches between the two tables. |
| Exact duplicate rows | None, ignoring the surrogate `id`. |
| Join multiplication | `campaign` → `communication_log` is 1:many on a primary key; 30 rows in, 30 out. Final query: 26 rows in, 26 distinct `log_id` out. |
| Recursive CTE correctness | Resolves exactly 7 campaigns to a root each — no cycles, no fan-out. |
| Ineligible-parent / eligible-child scenario | **Does not occur in this dataset** — every eligible child's parent chain is fully eligible. Cannot be empirically tested here; noted as a gap, not assumed away. |
| Chain-shape computed before vs. after the eligibility gate | Tested both orderings directly: family 9001 has 4 members counting all campaigns, 3 counting eligible-only — either way it's still `>1`, so the retry rule still applies. Both orderings give **22**. Kept "before the gate" in the final query because chain membership is a structural fact of `parent_id`, independent of approval status. |

---

## Alternative hypotheses tested and rejected

Every one of these was run against the *same* scope as the bridge above.

| # | Interpretation | Result | Verdict |
|---|---|---|---|
| A | Naive `COUNT(*)`, all eligible + ineligible rows | 30 | Bridge step 1 |
| B | `COUNT(*)`, eligible campaigns only | 26 | Bridge step 2 |
| C | Global `COUNT(DISTINCT customer_id)`, eligible only | **21** | **Rejected** — see below |
| D | Distinct (campaign, customer) pairs, eligible only | 25 | **Rejected** — dedupes per campaign row, not per underlying communication; still splits C3's chain into 3 |
| E | Root-only: `COUNT(*)` of rows under the root campaign, retry-child rows discarded entirely | **22** | **Rejected** — contradicts the written definition, and a counterfactual breaks it (below) |
| F | Delivered-only (`delivery_status = 900`), eligible only | **22** | **Rejected as the mechanism, retained as a documented ambiguity** — numerical coincidence, disproven by counterfactual (below) |
| G | **Retry-family-aware: dedupe within chains, standalone by row** | **22** | **Final method** |

### C — global distinct customer (21): rejected

**Why it's tempting:** three customers (C2, C3, D1) each appear under more than one
campaign. Deduplicating the customer column looks like the obvious fix.

**What disproves it:** it also collapses **C20**, who appears twice under standalone
campaign 9101 — both `delivery_status = 900`, ten days apart (Oct 10 and Oct 20), same
campaign, no parent, no children. That is not a retry; it is a second genuine send. This
interpretation destroys a real, delivered message. Being *one short* of 22 (21, not 22)
is exactly the evidence that exposed the standalone-vs-chain distinction.

**Per the data dictionary:** "A campaign with no retry chain at all... is a standalone
communication — every send under it is its own event, whether or not the same customer
appears twice." Global dedupe directly contradicts this sentence.

### D — distinct (campaign, customer) pairs (25): rejected

**Why it's tempting:** it looks like a safer, more conservative dedupe — dedupe within
a campaign, not globally.

**What disproves it:** it still fails to collapse C3's chain. C3 has one row each under
9001, 9002, 9003 — three *different* campaign ids, so `(campaign, customer)` treats
all three as distinct pairs. The data dictionary is explicit that a retry chain is
"the same underlying communication," not three. This interpretation under-collapses
retry chains while over-collapsing nothing — it just doesn't implement the retry-family
concept at all.

### E — root-only (22): rejected, despite matching the number

**What it means precisely:** ignore every retry-child campaign's rows entirely; only
count rows sent directly under the root campaign (`parent_id IS NULL`), using
`COUNT(*)`.

**Why it numerically matches on this dataset:** every customer in every retry family
here also has a row under that family's root campaign (they failed there first, then
were retried). So the root's own row count happens to already touch every customer the
whole chain ever reaches. That is a property of *this specific dataset*, not a rule.

**Why it is rejected, not just "an alternative":** the data dictionary defines
`target_base` as reachable customers across "a campaign **plus every retry chained off
it**" — it explicitly requires looking at the retry rows. Root-only does the opposite: it
throws every retry row away. It doesn't merely fail to match the docs by coincidence; it
contradicts the sentence that defines the metric.

**Counterfactual (run on a throwaway copy, real data untouched):** inserted one
synthetic row — a customer (`C99`) whose *only* attempt is under retry-child 9003, with
no row under root 9001 or child 9002 (a realistic scenario: a retry audience gets
expanded to include someone not in the original blast).

| Method | Result after adding C99 |
|---|---|
| Retry-family-aware (final method) | **23** — correctly gains the newly reached customer |
| Root-only | **22** — unchanged, silently misses C99 |

This is decisive: root-only doesn't just happen to differ in some hypothetical sense, it
demonstrably produces the wrong answer the moment the "root already contains everyone"
coincidence breaks.

### F — delivered-only (22): rejected as the mechanism, documented as an ambiguity

**Why it's tempting:** it sounds like "a qualifying send is one that actually went
through," and 900 = delivered is right there in the schema.

**Why it numerically matches on this dataset:** among the 26 eligible rows, 0
customers were never delivered, 20 have exactly one delivered row, and exactly 1 (C20)
has two — and C20 sits in the standalone campaign, where both of their rows count under
the correct method anyway. The two counting rules only need to agree on 20 of 21
customers to tie, and they do.

**Why it is rejected as the final method:**
1. The data dictionary never mentions delivery outcome in its definition of a
   qualifying send — the definition is entirely in terms of retry-chain membership.
2. Failed attempts are real, billed sends: all 4 `delivery_status = 1100` rows have
   `credit_used = 1`. A metric that silently drops billed attempts needs its own
   justification, which the docs don't give.
3. `target_base` reads as a *targeting* metric (who was reached), not a *deliverability*
   metric (who received it). Those are different things Finance would track separately.

**Counterfactual (same throwaway-copy technique, distinct from the root-only test):**
flip C3's final, successful attempt (log row `id = 6`, under 9003) from `900` to
`1100` — simulating a customer who was retried and never once succeeded.

| Method | Result after C3 never succeeds |
|---|---|
| Retry-family-aware (final method) | **22** — unchanged; C3 was still targeted, chain still resolves to 10 distinct customers |
| Delivered-only | **21** — drops by one |

**Why this is documented as an ambiguity rather than dismissed outright:** unlike
root-only, delivered-only does not contradict any sentence in the data dictionary — it
simply isn't required by it either. If Finance's own internal definition secretly is
"delivered only," this dataset cannot rule that out; it can only show that the two
readings tie *here* by coincidence and diverge on a single-row change. The way to
settle it for good is to ask Finance for one period where a retried customer never
succeeded — the two definitions predict different numbers there.

---

## The headline finding

**Three materially different counting rules — retry-family-aware, root-only, and
delivered-only — all land on exactly 22 on this dataset.** That is analytically
important precisely because it means *matching Finance's number is not proof of correct
logic*. Each of the three was tested against the data dictionary's text and against a
counterfactual; only the retry-family-aware rule survives both. The other two are
disproven, not merely "also correct."
