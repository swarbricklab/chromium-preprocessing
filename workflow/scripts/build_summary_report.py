#!/usr/bin/env python3
"""
Generate a summary report for Chromium-Preprocessing metrics.
Main workflow script that uses utility functions from summary_utils.py
"""
import pandas as pd
import matplotlib.pyplot as plt
from jinja2 import Environment, FileSystemLoader, select_autoescape
import os
import datetime
import sys
import shutil
import pathlib

# redirect into Snakemake log
log = open(snakemake.log[0], "w")
sys.stdout = sys.stderr = log

from summary_utils import metric_plot, df_to_html
print("Successfully imported summary_utils")

# --- Config ---
# Get paths from Snakemake
ge_summary_path = snakemake.input.combined_csv
template_path = snakemake.input.template
output_report_path = snakemake.output.summary_report
print(f"Input CSV: {ge_summary_path}")
print(f"Output report: {output_report_path}")

# --- Load data ---

print("Loading summary data...")
ge_df = pd.read_csv(ge_summary_path)
print(f"Loaded data from {ge_summary_path}, shape: {ge_df.shape}")
print(f"Columns: {list(ge_df.columns)}")
print(f"First few rows:")
print(ge_df.head())

# --- Jinja2 HTML template setup ---
# Update template path to use config['ref']['html']
html_dir = pathlib.Path(snakemake.config['ref']['html'])
env = Environment(
    loader=FileSystemLoader(html_dir),
    autoescape=select_autoescape(['html'])
)
template = env.get_template("summary_template.html")
print("Successfully loaded HTML template")

# --- Generate Plots and Tables ---
plots = {'gex': {}, 'adt': {}}
tables = {}

if ge_df is not None:
    print("Generating plots and tables...")
    # Gene Expression plots
    gex_cols_to_plot = [
        ('Estimated Number of Cells', False),
        ('Reads Mapped Confidently to Genome', True),  # This is a percentage
        ('Median UMI Counts per Cell', False),
        ('Median Genes per Cell', False),
        ('Mean Reads per Cell', False),
        ('Total Genes Detected', False)
    ]

    for col, is_percent in gex_cols_to_plot:
        print(f"Generating plot for: {col}")
        # Use stacked bar chart for "Estimated Number of Cells", grouped for others
        is_stacked = (col == 'Estimated Number of Cells')
        plots['gex'][col.replace(" ", "_").lower()] = metric_plot(
            ge_df, 'Pool', col, 'Capture', col, 
            y_percent=is_percent, stacked=is_stacked
        )

    # Generate table
    table_cols = ['Capture', 'Pool'] + [col for col, _ in gex_cols_to_plot]
    tables['ge_table'] = df_to_html(ge_df[table_cols])
    print("Successfully generated all plots and tables")
else:
    print("Warning: No data available, skipping plot generation")

# --- Render HTML report ---
template_vars = {
    "plots": plots,
    "tables": tables,
    "has_gex": ge_df is not None,
    "timestamp": datetime.datetime.now().isoformat(timespec="seconds")
}

html_out = template.render(**template_vars)
print("Successfully rendered HTML template")

# Write output
os.makedirs(os.path.dirname(output_report_path), exist_ok=True)
with open(output_report_path, "w") as f:
    f.write(html_out)

print(f"Report generated successfully: {output_report_path}")

log.close()
