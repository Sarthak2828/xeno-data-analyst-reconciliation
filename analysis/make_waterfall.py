"""
Regenerates analysis/reconciliation_waterfall.png.

Values are NOT hardcoded from memory - they are the output of the bridge
steps in sql/reconciliation_queries.sql, run against data/comm_log.db:
    step 0 (naive)            -> 30
    step 2 (eligibility gate) -> 26
    step 3b (retry dedupe)    -> 22

Run:
    python analysis/make_waterfall.py
"""
import sqlite3
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import matplotlib.ticker as mticker

DB = "data/comm_log.db"

NAIVE_SQL = """
SELECT COUNT(*)
FROM communication_log l
JOIN campaign c ON c.id = l.communication_id
WHERE l.merchant_id = 501 AND l.communication_type = '2'
  AND l.sent_time >= '2026-10-01' AND l.sent_time < '2026-11-01'
  AND c.name LIKE '%Diwali%'
"""

AFTER_GATE_SQL = """
SELECT COUNT(*)
FROM communication_log l
JOIN campaign c ON c.id = l.communication_id
WHERE l.merchant_id = 501 AND l.communication_type = '2'
  AND l.sent_time >= '2026-10-01' AND l.sent_time < '2026-11-01'
  AND c.name LIKE '%Diwali%'
  AND c.creation_status IN ('approved','aborted','resumed','stopped')
  AND c.processing_status = 'processed'
"""

FINAL_SQL = open("sql/final_query.sql", encoding="utf-8").read()


def scalar(con, sql):
    return con.execute(sql).fetchone()[0]


def main():
    con = sqlite3.connect(DB)
    naive = scalar(con, NAIVE_SQL)
    after_gate = scalar(con, AFTER_GATE_SQL)
    final = scalar(con, FINAL_SQL)
    con.close()

    print(f"naive={naive}  after_gate={after_gate}  final={final}")
    assert (naive, after_gate) == (30, 26), "Bridge inputs changed - regenerate the chart intentionally."

    steps = ["Naive\ncount", "Eligibility\ngate", "Retry-chain\ndedupe", "Final\ntarget_base"]
    values = [naive, after_gate, final, final]
    deltas = [naive, after_gate - naive, final - after_gate, 0]

    fig, ax = plt.subplots(figsize=(7, 4.2), dpi=150)

    running, bottoms, heights, colors = 0, [], [], []
    for i, (v, d) in enumerate(zip(values, deltas)):
        if i == 0:
            bottoms.append(0); heights.append(v); colors.append("#4C72B0")
            running = v
        elif i == len(values) - 1:
            bottoms.append(0); heights.append(v); colors.append("#55A868")
        else:
            bottoms.append(running + d); heights.append(-d); colors.append("#C44E52")
            running += d

    ax.bar(steps, heights, bottom=bottoms, color=colors, width=0.6,
           edgecolor="white", linewidth=0.8)

    level_after = [naive, after_gate, final, final]
    for i in range(len(steps) - 1):
        ax.plot([i + 0.3, i + 0.7], [level_after[i], level_after[i]],
                 color="#999999", linewidth=1, linestyle="--")

    for i, (b, h, v) in enumerate(zip(bottoms, heights, values)):
        ax.text(i, b + h + 0.6, str(v), ha="center", va="bottom",
                 fontsize=11, fontweight="bold")
    for i, d in enumerate(deltas):
        if i not in (0, len(deltas) - 1) and d != 0:
            ax.text(i, bottoms[i] + heights[i] / 2, f"{d}", ha="center", va="center",
                     fontsize=9, color="white", fontweight="bold")

    ax.set_ylim(0, max(values) + 4)
    ax.set_ylabel("target_base (qualifying sends)")
    ax.set_title("Reconciliation bridge: naive count → Finance's target_base",
                  fontsize=11, pad=12)
    ax.spines["top"].set_visible(False)
    ax.spines["right"].set_visible(False)
    ax.yaxis.set_major_locator(mticker.MultipleLocator(5))
    ax.grid(axis="y", linestyle=":", alpha=0.4)

    plt.tight_layout()
    out = "analysis/reconciliation_waterfall.png"
    plt.savefig(out)
    print("saved", out)


if __name__ == "__main__":
    main()
