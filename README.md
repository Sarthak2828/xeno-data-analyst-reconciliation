# Xeno Data Analyst Assignment — Campaign Reconciliation

**Candidate:** Sarthak Gaba
**Role:** Data Analyst Internship
**Objective:** reconcile Finance's `target_base` of **22** for merchant 501, October
2026, Diwali campaigns, from the raw send data — and explain the gap, not just match
the number.
**Tools:** SQLite / SQL, Python (pandas, matplotlib)
**Final reconciled result:** **`target_base = 22`**, verified by
[`sql/final_query.sql`](sql/final_query.sql) against [`data/comm_log.db`](data/comm_log.db).

## The problem

A naive query against the raw data returns **30**. Finance says the true number is
**22**. The task: reproduce 22 from the data itself and show the investigation that
gets there — not just land on the right number.

## The data

Two tables (schema in [`DATA_DICTIONARY.md`](DATA_DICTIONARY.md)):

- **`campaign`** (7 rows) — one row per marketing blast. `parent_id` marks a campaign
  as a retry of an earlier one; chains can be more than one level deep.
- **`communication_log`** (30 rows) — one row per individual SMS attempt, linked to its
  campaign, with a delivery outcome (`900` = delivered, `1100` = failed).

## Methodology

`target_base` is counted per **underlying communication** — a root campaign plus every
campaign chained off it via `parent_id` — not per raw log row:

- **Retry chain** (>1 campaign in the family): count **distinct customers**. Several
  attempts to reach one person is one qualifying send.
- **Standalone campaign** (no parent, no children): count **every send row**. A repeat
  customer under a standalone campaign is two genuine sends.
- A campaign only counts once its `creation_status` is finalized **and**
  `processing_status = 'processed'`.

## Reconciliation bridge

```
   30                    26                       22
Naive count  ──eligibility gate──►  ──retry-family dedupe──►  Final target_base
             (drop 1 unapproved      (collapse repeat attempts
              campaign, -4)           within a chain only, -4)
```

| Step | Description | Result | Adjustment |
|---|---|---|---|
| 1 | Naive/scoped communication count | 30 | — |
| 2 | Remove campaign-ineligible records | 26 | −4 |
| 3 | Apply retry-family deduplication | **22** | −4 |

Full evidence — including the reasoning trail of what was tried, what didn't match, and
why — is in [`analysis/reconciliation_bridge.md`](analysis/reconciliation_bridge.md).
A chart of the same bridge is at
[`analysis/reconciliation_waterfall.png`](analysis/reconciliation_waterfall.png).

## Why other approaches were rejected

Matching Finance's number isn't proof the logic is correct — three different counting
rules land on 22 here. Each was tested against the data dictionary's text and a
counterfactual before being accepted or rejected:

| Approach | Result | Verdict |
|---|---|---|
| Global `COUNT(DISTINCT customer_id)` | 21 | Rejected — wrongly merges a customer's two genuine standalone sends |
| Per-campaign distinct (campaign, customer) | 25 | Rejected — doesn't collapse a multi-level retry chain at all |
| Root-only (ignore every retry row, count the root campaign alone) | 22 | Rejected — contradicts the data dictionary's own definition; breaks on a customer reached only via a retry |
| Delivered-only (`delivery_status = 900` only) | 22 | Rejected as the mechanism — not required by the docs, and breaks when a retried customer never succeeds |
| **Retry-family-aware (final method)** | **22** | **Accepted** |

Both interpretations that tie the correct answer are disproven with a concrete
counterfactual — run on a disposable copy of the database, never the shipped one — in
[`sql/counterfactuals.sql`](sql/counterfactuals.sql).

## Key finding

The same SQL idiom (`COUNT(DISTINCT customer_id)`) is correct inside a retry chain and
wrong inside a standalone campaign. The shape of the campaign graph — not the SQL
pattern — decides which rule applies. That's also why two structurally different rules
can coincidentally tie the right answer without being correct.

## How to reproduce

```bash
pip install -r requirements.txt

sqlite3 -header -column data/comm_log.db < sql/exploration.sql             # data profile
sqlite3 -header -column data/comm_log.db < sql/reconciliation_queries.sql  # every bridge step + rejected alternatives
sqlite3 -header -column data/comm_log.db < sql/final_query.sql             # -> 22

python analysis/make_waterfall.py   # regenerates the chart from live queries
```

`sql/counterfactuals.sql` reproduces the two divergence tests that disprove the rival
interpretations — instructions to run it against a disposable copy are in the file
header.

`analysis/reconciliation_analysis.ipynb` walks through the same investigation
interactively (built for Google Colab; edit the two CSV paths in the config cell).

## File map

```
├── README.md                    you are here
├── DATA_DICTIONARY.md            schema + business rules, as supplied
├── requirements.txt
├── .gitignore
├── data/                         raw data, unmodified
│   ├── campaign.csv
│   ├── communication_log.csv
│   ├── comm_log.db
│   └── generate_dataset.py       provided generator (context only — no aggregation logic)
├── sql/
│   ├── final_query.sql           the answer: returns 22
│   ├── exploration.sql           Phase 1 data profiling
│   ├── reconciliation_queries.sql  every bridge step + rejected alternatives, runnable
│   └── counterfactuals.sql       the two tests that disprove the rival interpretations
└── analysis/
    ├── reconciliation_bridge.md  full investigation, evidence, rejected alternatives
    ├── reconciliation_waterfall.png
    ├── make_waterfall.py         regenerates the chart from live queries
    └── reconciliation_analysis.ipynb   interactive walkthrough (Colab)
```

## Data integrity

`data/` is byte-for-byte identical to the originally supplied files — verified by
checksum. All counterfactual testing ran on disposable copies outside this repository.
