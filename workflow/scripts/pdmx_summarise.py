"""Roll the per-capture predemux QC tables up into one cohort table.

One row per capture (in captures-sheet order):
  - the filter outcome from predemux_filter_seurat (cells in/out, discarded per filter);
  - each threshold sweep from predemux_gather_qc_metrics, pivoted wide. The columns are
    named for the comparison pdmx_metrics.R actually makes: min-type filters count cells
    with value <= threshold (`sweep_genes_le_300`), max-type count value >= threshold
    (`sweep_mito_ge_10`). Values are the proportion of the capture's cells.

The per-capture inputs stay temp(); this table is what persists.
"""
import logging
import pandas as pd

logging.basicConfig(filename=str(snakemake.log[0]), level=logging.INFO,
                    format="%(asctime)s %(levelname)s %(message)s")

captures = list(snakemake.params.captures)
SWEEPS = (("genes", "le", snakemake.input.gene_csvs),
          ("mito", "ge", snakemake.input.mito_csvs),
          ("umi", "le", snakemake.input.umi_csvs))


def fmt(t):
    return f"{t:g}"


rows = []
for i, cap in enumerate(captures):
    stats = pd.read_csv(snakemake.input.filter_stats_csvs[i])
    row = {"capture": cap, **(stats.iloc[0].to_dict() if len(stats) else {})}
    for name, op, files in SWEEPS:
        sweep = pd.read_csv(files[i])
        for t, p in zip(sweep["threshold"], sweep["cumulative_prop_discarded"]):
            row[f"sweep_{name}_{op}_{fmt(t)}"] = p
    rows.append(row)

df = pd.DataFrame(rows)
# Captures with 0 cells have empty sweeps; keep a stable column set and order.
cols = ["capture"] + [c for c in df.columns if c != "capture" and not c.startswith("sweep_")]
for name, op, _ in SWEEPS:
    sw = [c for c in df.columns if c.startswith(f"sweep_{name}_{op}_")]
    cols += sorted(sw, key=lambda c: float(c.rsplit("_", 1)[1]))
df = df.reindex(columns=cols)
for c in df.columns:
    if c.startswith(("total_initial", "cells_discarded", "total_final")):
        df[c] = df[c].astype("Int64")
df.to_csv(str(snakemake.output.summary), index=False)
logging.info("wrote %d captures x %d columns to %s", len(df), df.shape[1], snakemake.output.summary)
