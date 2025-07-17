#!/usr/bin/env python3
"""
Generate a comprehensive summary report for Chromium-Preprocessing metrics.
Supports both count and multi mode formats with multiple library types.
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

from cellranger_summary_utils import metric_plot, df_to_html, prepare_data_for_plotting, create_section_plots
print("Successfully imported summary_utils")

# --- Config ---
# Get paths from Snakemake
summary_csv_path = snakemake.input.combined_csv
output_report_path = snakemake.output.cellranger_summary_report
script_dir = os.path.dirname(os.path.abspath(__file__))
print(f"Input CSV: {summary_csv_path}")
print(f"Output report: {output_report_path}")
print(f"Script directory: {script_dir}")

# --- Load and analyze data ---
print(f"Checking if file exists: {summary_csv_path}")
if not os.path.exists(summary_csv_path):
    print(f"Error: Input file does not exist: {summary_csv_path}")
    sys.exit(1)

print("File exists, loading data...")
df = pd.read_csv(summary_csv_path)
print(f"Loaded data from {summary_csv_path}, shape: {df.shape}")
print(f"Columns: {list(df.columns)}")

# Get data format from snakemake params
data_format = snakemake.params.mode
print(f"Using data format from config: {data_format}")

if data_format == 'multi':
    library_types = df['Library Type'].dropna().unique()
    print(f"Available library types: {library_types}")
else:
    library_types = ['Gene Expression']  # Count mode only has gene expression

# --- Helper functions ---

# --- Configuration for different sections ---
section_configs = {
    'Gene Expression': {
        'metrics': [
            ('Cells', False),
            ('Confidently mapped reads in cells', True),
            ('Median UMI counts per cell', False),
            ('Median genes per cell', False),
            ('Mean reads per cell', False),
            ('Total genes detected', False)
        ]
    },
    'Antibody Capture': {
        'metrics': [
            ('Antibody reads in cells', True),
            ('Fraction antibody reads', True),
            ('Fraction antibody reads in aggregate barcodes', True),
            ('Mean antibody reads usable per cell', False),
            ('Median UMI counts per cell', False),
            ('Number of reads from cells associated with this sample', False)
        ]
    },
    'VDJ B': {
        'metrics': [
            ('Cells with productive TRA contig', True),
            ('Cells with productive TRB contig', True),
            ('Cells with productive V-B spanning pair', True),
            ('Fraction reads in cells', True),
            ('Median TRA UMIs per Cell', False),
            ('Median TRB UMIs per Cell', False)
        ]
    },
    'VDJ T': {
        'metrics': [
            ('Cells with productive TRA contig', True),
            ('Cells with productive TRB contig', True),
            ('Cells with productive V-J spanning pair', True),
            ('Fraction reads in cells', True),
            ('Median TRA UMIs per Cell', False),
            ('Median TRB UMIs per Cell', False)
        ]
    }
}

# For count mode compatibility
count_mode_config = {
    'Gene Expression': {
        'metrics': [
            ('Estimated Number of Cells', False),
            ('Reads Mapped Confidently to Genome', True),
            ('Median UMI Counts per Cell', False),
            ('Median Genes per Cell', False),
            ('Mean Reads per Cell', False),
            ('Total Genes Detected', False)
        ]
    }
}

# --- Jinja2 HTML template setup ---
env = Environment(
    loader=FileSystemLoader(script_dir),
    autoescape=select_autoescape(['html'])
)
template = env.get_template("summary_template.html")
print("Successfully loaded HTML template")

# --- Generate Plots and Tables ---
all_plots = {}
all_tables = {}
sections = []

if data_format == 'multi':
    # Process each library type
    for library_type in library_types:
        if library_type in section_configs:
            print(f"\nProcessing {library_type} section...")
            plots, table = create_section_plots(df, data_format, library_type, section_configs[library_type])
            
            section_key = library_type.lower().replace(' ', '_')
            all_plots[section_key] = plots
            all_tables[f'{section_key}_table'] = table
            sections.append({
                'name': library_type,
                'key': section_key,
                'has_data': bool(plots)
            })
            print(f"Generated {len(plots)} plots for {library_type}")
else:
    # Count mode - process as Gene Expression
    print("\nProcessing count mode data as Gene Expression...")
    
    # For count mode, assume the data is already in the right format
    ge_df = df.copy()
    
    # Add Pool and Replicate if missing
    if 'Pool' not in ge_df.columns and 'Capture' in ge_df.columns:
        # Extract pool from capture name or use a default
        ge_df['Pool'] = ge_df['Capture'].str.extract(r'(\w+)_').fillna('default_pool')
    
    if 'Replicate' not in ge_df.columns and 'Capture' in ge_df.columns:
        ge_df['Replicate'] = ge_df['Capture'].str.extract(r'.*_(\w)$').fillna('1')
    
    # Generate plots using count mode configuration
    plots = {}
    for col, is_percent in count_mode_config['Gene Expression']['metrics']:
        if col in ge_df.columns:
            print(f"Generating plot for: {col}")
            is_stacked = (col == 'Estimated Number of Cells')
            plots[col.replace(" ", "_").lower()] = metric_plot(
                ge_df, 'Pool', col, 'Capture', col, 
                y_percent=is_percent, stacked=is_stacked
            )
    
    # Generate table
    table_cols = ['Capture', 'Pool'] + [col for col, _ in count_mode_config['Gene Expression']['metrics'] if col in ge_df.columns]
    table_html = df_to_html(ge_df[table_cols]) if table_cols else df_to_html(ge_df)
    
    all_plots['gene_expression'] = plots
    all_tables['gene_expression_table'] = table_html
    sections.append({
        'name': 'Gene Expression',
        'key': 'gene_expression', 
        'has_data': bool(plots)
    })

print(f"\nGenerated data for {len(sections)} sections")
print(f"Total plots: {sum(len(all_plots[s['key']]) for s in sections if s['has_data'])}")

# --- Render HTML report ---
template_vars = {
    "plots": all_plots,
    "tables": all_tables,
    "sections": sections,
    "data_format": data_format,
    "has_data": any(s['has_data'] for s in sections),
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
