# Xeno Data Analyst Assignment — Campaign Reconciliation

**Candidate:** Sarthak Gaba
**Role:** Data Analyst Internship
**Objective:** reconcile Finance's `target_base` of **22** for merchant 501, October
2026, Diwali campaigns, from the raw send data, and explain how I got there.

The obvious query gives **30**. Finance says the real number is **22**. This repo is
the path between those two numbers, including the wrong turns.

## The data

Two tables (full schema in [`DATA_DICTIONARY.md`](DATA_DICTIONARY.md)):

- **`campaign`** (7 rows) — one row per marketing blast. `parent_id` marks a campaign as
  a retry of an earlier one, and a chain can be more than one level deep.
- **`communication_log`** (30 rows) — one row per individual SMS attempt, linked to a
  campaign, with a delivery outcome (`900` delivered, `1100` failed).

## The rule, in plain terms

`target_base` isn't "count the rows." It's counted per **underlying communication** — a
campaign plus every retry chained off it:

- Inside a **retry chain** (more than one campaign in the family): count each customer
  **once**, however many attempts it took.
- Inside a **standalone campaign** (no parent, no children): count **every row** — a
  repeat customer there is two genuine sends, not a retry.
- A campaign only counts once it's actually approved *and* fully processed.

## The bridge

```
30  →  drop the unapproved campaign (-4)  →  26  →  dedupe within retry chains only (-4)  →  22
```

| Step | What I checked | Result |
|---|---|---|
| Naive count | Every send row in scope | 30 |
| Eligibility filter | Campaign 9004 is still pending approval | 26 |
| *(wrong turn)* Global dedupe | Just count unique customers | 21 |
| Retry-chain dedupe | Dedupe only inside a chain, not standalone | **22** |

Full reasoning for each step, with the actual query for it, is in
[`sql/reconciliation/`](sql/reconciliation/README.md) — I split it into one small file
per step instead of one long script, since the point of this assignment is the path,
not just the final number.

The full writeup with evidence is in
[`analysis/reconciliation_bridge.md`](analysis/reconciliation_bridge.md), and a chart of
the same bridge is at
[`analysis/reconciliation_waterfall.png`](analysis/reconciliation_waterfall.png).

## Why I didn't stop at 22

While checking other ways to slice this, I found two more approaches that *also* land
on 22 — which worried me, since it means matching Finance's number by itself doesn't
prove the logic is right.

| Approach | Result | Problem |
|---|---|---|
| Ignore retries, count only the original campaign | 22 | Ties by coincidence — breaks the moment a customer is only ever reached through a retry |
| Only count delivered messages | 22 | Ties by coincidence — breaks the moment a retried customer never once succeeds |

I broke both of these on purpose in [`sql/counterfactuals.sql`](sql/counterfactuals.sql)
by tweaking a copy of the data slightly and checking whether they still agreed with my
actual method. Both stopped agreeing.

## How to run this yourself

```bash
pip install -r requirements.txt

# the bridge, one step at a time
sqlite3 -header -column data/comm_log.db < sql/reconciliation/step1_naive_count.sql
sqlite3 -header -column data/comm_log.db < sql/reconciliation/step2_eligibility_filter.sql
sqlite3 -header -column data/comm_log.db < sql/reconciliation/step3_final_dedupe.sql

# the actual answer
sqlite3 data/comm_log.db < sql/final_query.sql   # -> 22

# regenerate the chart
python analysis/make_waterfall.py
```

`sql/counterfactuals.sql` has instructions in its header for running the two
stress-tests against a disposable copy of the database.

`analysis/reconciliation_analysis.ipynb` walks through the whole thing interactively —
built for Colab, just edit the two CSV paths in the config cell.

## What surprised me

Not the data itself, which is small and clean — it's that three different counting
rules all land on 22. The thing that actually separates the right one from the other two
is customer **C20**, who has two genuine, delivered messages under one standalone
campaign, ten days apart. Deduping customers globally (my first attempt) quietly
deletes one of those and gives 21. Understanding *why* C20 shouldn't be deduped is what
led to the actual rule — and it's also the reason the two other 22-answers don't hold up
once you test them against slightly different data.

## Repo layout

```
├── README.md                  you're here
├── DATA_DICTIONARY.md          schema + business rules, as given
├── requirements.txt
├── data/                       raw data, unmodified
│   ├── campaign.csv
│   ├── communication_log.csv
│   ├── comm_log.db
│   └── generate_dataset.py     the script that made this data (context only, no answer in it)
├── sql/
│   ├── final_query.sql         the answer — returns 22
│   ├── counterfactuals.sql     the two stress tests that rule out the other 22s
│   └── reconciliation/         the bridge, one query per file
│       ├── README.md
│       ├── step1_naive_count.sql
│       ├── step2_eligibility_filter.sql
│       ├── rejected_global_distinct.sql
│       ├── step3_final_dedupe.sql
│       ├── alt_per_campaign_distinct.sql
│       ├── alt_root_only.sql
│       └── alt_delivered_only.sql
└── analysis/
    ├── reconciliation_bridge.md
    ├── reconciliation_waterfall.png
    ├── make_waterfall.py
    └── reconciliation_analysis.ipynb
```

## Data integrity

`data/` is byte-for-byte identical to what was supplied — checked by hash. All the
stress-testing in `counterfactuals.sql` runs on a disposable copy, never this database.
