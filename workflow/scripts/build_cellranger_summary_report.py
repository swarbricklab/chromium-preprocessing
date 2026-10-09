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
import shutil

# redirect into Snakemake log
log = open(snakemake.log[0], "w")
sys.stdout = sys.stderr = log

from cellranger_summary_utils import metric_plot, df_to_html, prepare_data_for_plotting, create_section_plots, report_timestamp
print("Successfully imported summary_utils")

# --- Config ---
# Get paths from Snakemake
summary_csv_path = snakemake.input.combined_csv
summary_template_path = snakemake.input.summary_template
css_file_path = snakemake.input.css_file
output_report_path = snakemake.output.cellranger_summary_report
template_dir = os.path.dirname(summary_template_path)
print(f"Input CSV: {summary_csv_path}")
print(f"Output report: {output_report_path}")
print(f"Template directory: {template_dir}")

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

# Determine index columns and actual column names for plotting based on data format
if data_format == 'multi':
    if 'Sample' in df.columns:
        # Use Sample as individual points, Capture as grouping
        index_cols = ['Sample', 'Capture']
        plot_hue_col = 'Sample'      # Individual samples
        plot_x_col = 'Capture'       # Groups (captures)
    else:
        # Fallback to original behavior
        index_cols = ['Capture', 'Pool']
        plot_hue_col = 'Capture'     # Individual captures
        plot_x_col = 'Pool'          # Groups (pools)
    library_types = df['Library Type'].dropna().unique()
    print(f"Available library types: {library_types}")
else:
    # Count mode
    index_cols = ['Capture', 'Pool']
    plot_hue_col = 'Capture'         # Individual captures
    plot_x_col = 'Pool'              # Groups (pools)
    library_types = ['Gene Expression']  # Count mode only has gene expression

print(f"Using index columns: {index_cols}")
print(f"Plot columns - x (groups): {plot_x_col}, hue (individuals): {plot_hue_col}")

# --- Helper functions ---

# --- Jinja2 HTML template setup ---
env = Environment(
    loader=FileSystemLoader(template_dir),
    autoescape=select_autoescape(['html'])
)
template = env.get_template("summary_template.html")
print("Successfully loaded HTML template")

# --- Generate Plots and Tables ---
all_plots = {}
all_tables = {}
sections = []

if data_format == 'multi':
    # Auto-discover sections based on data combinations
    print("\nAuto-discovering sections from multi mode data...")
    
    # Get unique combinations of Category, Library Type, and Grouped By
    # Use dropna=False to include NaN values (important for Cells category)
    section_combinations = df.groupby(['Category', 'Library Type', 'Grouped By'], dropna=False).size().reset_index(name='count')
    print(f"Found {len(section_combinations)} unique section combinations:")
    print(section_combinations[['Category', 'Library Type', 'Grouped By']])
    
    for _, row in section_combinations.iterrows():
        category = row['Category']
        library_type = row['Library Type']
        grouped_by = row['Grouped By']
        
        # Create section name and key
        if category == 'Cells':
            section_name = library_type
            section_key = library_type.lower().replace(' ', '_')
        elif category == 'Library':
            if pd.isna(grouped_by) or grouped_by == '':
                section_name = f"{library_type} Library Metrics"
                section_key = f"{library_type.lower().replace(' ', '_')}_library"
            else:
                section_name = f"{library_type} Library Metrics by {grouped_by}"
                section_key = f"{library_type.lower().replace(' ', '_')}_library_{grouped_by.lower().replace(' ', '_')}"
        else:
            section_name = f"{library_type} {category}"
            section_key = f"{library_type.lower().replace(' ', '_')}_{category.lower().replace(' ', '_')}"
        
        print(f"\nProcessing section: {section_name}")
        print(f"  Category: {category}, Library Type: {library_type}, Grouped By: {grouped_by}")
        
        # Get all metrics for this combination
        section_data = df[
            (df['Category'] == category) & 
            (df['Library Type'] == library_type) & 
            (df['Grouped By'].fillna('') == (grouped_by if pd.notna(grouped_by) else ''))
        ]
        
        # Get unique metrics for this section
        unique_metrics = section_data['Metric Name'].unique()
        print(f"  Found {len(unique_metrics)} metrics: {list(unique_metrics)[:5]}{'...' if len(unique_metrics) > 5 else ''}")
        
        # Create dynamic configuration for this section
        # Check if metric values end with % to determine if it's a percentage metric
        metric_configs = []
        for metric in unique_metrics:
            # Get sample values for this metric to check if they're percentages
            sample_values = section_data[section_data['Metric Name'] == metric]['Metric Value'].dropna()
            if not sample_values.empty:
                # Check if any of the values end with %
                is_percentage = any(str(val).endswith('%') for val in sample_values.head(3))
            else:
                is_percentage = False
            metric_configs.append((metric, is_percentage))
        
        section_config = {'metrics': metric_configs}
        
        # Generate plots and table for this section
        plots, table = create_section_plots(df, index_cols, library_type, section_config, plot_x_col, plot_hue_col, category, grouped_by)
        
        if plots or table:  # Only add if we have data
            all_plots[section_key] = plots
            all_tables[f'{section_key}_table'] = table
            sections.append({
                'name': section_name,
                'key': section_key,
                'has_data': bool(plots)
            })
            print(f"  Generated {len(plots)} plots for {section_name}")
        else:
            print(f"  No data generated for {section_name}")
            
    print(f"\nTotal sections created: {len(sections)}")
else:
    # Count mode - process as Gene Expression
    print("\nProcessing count mode data as Gene Expression...")
    
    # For count mode, ensure required columns exist
    ge_df = df.copy()
    
    # Add Pool if missing
    if 'Pool' not in ge_df.columns and 'Capture' in ge_df.columns:
        # Extract pool from capture name or use a default
        ge_df['Pool'] = ge_df['Capture'].str.extract(r'(\w+)_').fillna('default_pool')


    # Get all numeric columns (excluding index columns)
    metric_columns = [col for col in ge_df.columns if col not in index_cols]
    print(f"  Found {len(metric_columns)} metrics: {list(metric_columns)[:5]}{'...' if len(metric_columns) > 5 else ''}")
    
    # Create dynamic configuration - detect percentages from actual data values
    # Check a sample of non-null values to determine if column contains percentages
    count_mode_config = {
        'metrics': []
    }
    
    for metric in metric_columns:
        # Check if any values in this column end with %
        sample_values = ge_df[metric].dropna().astype(str).head(10)
        is_percentage = any(val.strip().endswith('%') for val in sample_values)
        count_mode_config['metrics'].append((metric, is_percentage))
        if is_percentage:
            print(f"  Detected percentage metric: {metric}")
            
    print(f"  Total metrics: {len(count_mode_config['metrics'])}, percentages: {sum(1 for _, is_pct in count_mode_config['metrics'] if is_pct)}")
    
    # Use the same utility function as multi mode for consistency
    plots, table_html = create_section_plots(ge_df, index_cols, None, count_mode_config, plot_x_col, plot_hue_col)
    
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
    "timestamp": report_timestamp()
}

html_out = template.render(**template_vars)
print("Successfully rendered HTML template")

# Write output
os.makedirs(os.path.dirname(output_report_path), exist_ok=True)
with open(output_report_path, "w") as f:
    f.write(html_out)

print(f"Report generated successfully: {output_report_path}")

log.close()
