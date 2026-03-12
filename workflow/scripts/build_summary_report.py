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

# redirect into Snakemake log
log = open(snakemake.log[0], "w")
sys.stdout = sys.stderr = log

from summary_utils import metric_plot, df_to_html
print("Successfully imported summary_utils")

# --- Config ---
# Get paths from Snakemake
ge_summary_path = snakemake.input.combined_csv
output_report_path = snakemake.output.summary_report
script_dir = os.path.dirname(os.path.abspath(__file__))
print(f"Input CSV: {ge_summary_path}")
print(f"Output report: {output_report_path}")
print(f"Script directory: {script_dir}")

# --- Load data ---
print(f"Checking if file exists: {ge_summary_path}")
if os.path.exists(ge_summary_path):
    print("File exists, loading data...")
    ge_df = pd.read_csv(ge_summary_path)
    print(f"Loaded data from {ge_summary_path}, shape: {ge_df.shape}")
    print(f"Columns: {list(ge_df.columns)}")
    print(f"First few rows:")
    print(ge_df.head())
else:
    print(f"Warning: Input file does not exist: {ge_summary_path}")
    ge_df = None

# --- Jinja2 HTML template setup ---
env = Environment(
    loader=FileSystemLoader(script_dir),
    autoescape=select_autoescape(['html'])
)
template = env.get_template("summary_template.html")
print("Successfully loaded HTML template")

# --- Generate Plots and Tables ---
plots = {'gex': {}, 'adt': {}}
tables = {}

if ge_df is not None:
    print("Generating plots and tables...")

    # Detect long-format (cellranger multi) vs wide-format (cellranger count)
    if 'Metric Name' in ge_df.columns and 'Metric Value' in ge_df.columns:
        print("Detected long-format CSV (cellranger multi), pivoting to wide format...")
        # Filter to Cells category, Gene Expression only, and no sub-grouping
        cell_metrics = ge_df[
            (ge_df['Category'] == 'Cells') &
            (ge_df['Library Type'] == 'Gene Expression') &
            (ge_df['Grouped By'].isna() | (ge_df['Grouped By'] == ''))
        ].copy()
        # Map long-format metric names to wide-format column names
        metric_name_map = {
            'Cells': 'Estimated Number of Cells',
            'Confidently mapped to genome': 'Reads Mapped Confidently to Genome',
            'Median UMI counts per cell': 'Median UMI Counts per Cell',
            'Median genes per cell': 'Median Genes per Cell',
            'Mean reads per cell': 'Mean Reads per Cell',
            'Total genes detected': 'Total Genes Detected',
        }
        cell_metrics['Metric Name'] = cell_metrics['Metric Name'].map(metric_name_map)
        cell_metrics = cell_metrics.dropna(subset=['Metric Name'])
        # Pivot to wide format
        id_cols = [c for c in ['Sample', 'Capture', 'Pool'] if c in cell_metrics.columns]
        ge_df = cell_metrics.pivot_table(
            index=id_cols, columns='Metric Name', values='Metric Value', aggfunc='first'
        ).reset_index()
        ge_df.columns.name = None
        print(f"Pivoted data shape: {ge_df.shape}")
        print(f"Pivoted columns: {list(ge_df.columns)}")

    # Use 'Pool' as x-axis grouping if available, otherwise fall back to 'Capture'
    has_pool = 'Pool' in ge_df.columns
    x_col = 'Pool' if has_pool else 'Capture'
    hue_col = 'Capture' if has_pool else 'Sample'
    print(f"Using '{x_col}' as x-axis grouping column, '{hue_col}' as hue")

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
            ge_df, x_col, col, hue_col, col, 
            y_percent=is_percent, stacked=is_stacked
        )

    # Generate table
    table_cols = [x_col] + ([hue_col] if hue_col != x_col else []) + [col for col, _ in gex_cols_to_plot]
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
