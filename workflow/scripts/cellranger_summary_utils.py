#!/usr/bin/env python3
"""
Utility functions for generating summary report plots and tables.
Functions are ordered by their level of abstraction:
  1. Low-level data cleaning helpers
  2. Data preparation
  3. Primitive plotting utilities
  4. HTML conversion helper
  5. High-level section builder
"""
import os
import datetime
import pandas as pd
import matplotlib.pyplot as plt
import seaborn as sns
import numpy as np
import base64
from io import BytesIO


def report_timestamp():
    """ISO-8601 timestamp for report headers.

    Honors SOURCE_DATE_EPOCH (the reproducible-builds convention): when set, the
    reports are stamped with that fixed time so repeated runs are byte-identical
    (used by run_test.sh for the golden comparison). Otherwise the current local
    time is used.
    """
    epoch = os.environ.get("SOURCE_DATE_EPOCH")
    if epoch:
        return datetime.datetime.utcfromtimestamp(int(epoch)).isoformat(timespec="seconds")
    return datetime.datetime.now().isoformat(timespec="seconds")


# 1. Low-level data cleaning helpers

def clean_numeric_column(series):
    """Clean numeric (count) columns to float.

    Handles Cell Ranger's string metric formats: plain "12,799", and the
    count-with-fraction form "12799 (77.0%)" used in multi/OCM summaries, where
    the leading number is the count we want to plot.
    """
    if series.dtype == 'object':  # String data
        # Take the leading numeric token (before any space/parenthesis),
        # dropping thousands separators.
        extracted = (series.astype(str)
                           .str.replace(',', '', regex=False)
                           .str.extract(r'^\s*([-+]?\d*\.?\d+)')[0])
        return extracted.astype(float)
    else:
        return series.astype(float)


def clean_percentage_column(series):
    """Clean percentage columns to float on a 0-1 scale.

    Handles plain "98.2%" and the count-with-fraction form "12799 (77.0%)"
    (multi/OCM), where the percentage is the number immediately before '%'.
    """
    if series.dtype == 'object':  # String data like "98.2%" or "12799 (77.0%)"
        extracted = (series.astype(str)
                           .str.replace(',', '', regex=False)
                           .str.extract(r'([-+]?\d*\.?\d+)\s*%')[0])
        return extracted.astype(float) / 100
    else:
        return series.astype(float)


# 2. Data preparation

def prepare_data_for_plotting(df, index_cols, library_type=None, grouped_by=None, category=None):
    """
    Prepare and filter data for plotting.
    Converts from long format (Metric Name/Value) to wide format for easy plotting.
    
    Parameters:
    - df: DataFrame in long format with Metric Name and Metric Value columns
    - index_cols: List of column names to use as index in pivot (e.g., ['Sample', 'Capture'] or ['Capture', 'Pool'])
    - library_type: Filter by Library Type (for multi mode)
    - grouped_by: Filter by Grouped By value (can be None, empty string, or specific value)
    - category: Filter by Category
    
    Returns:
    - pivot_df: DataFrame in wide format with metrics as columns
    """
    print(f"Preparing data for plotting. Library type: {library_type}, Grouped by: {grouped_by}, Category: {category}")
    print(f"Input data shape: {df.shape}")
    print(f"Using index columns: {index_cols}")
    
    filtered_df = df.copy()
    
    # Check if data is in long format (multi mode) or wide format (count mode)
    is_long_format = 'Metric Name' in filtered_df.columns and 'Metric Value' in filtered_df.columns
    
    if is_long_format:
        # Multi mode data - apply filters
        if library_type:
            filtered_df = filtered_df[filtered_df['Library Type'] == library_type]
        
        if grouped_by is not None:  # Can be empty string
            if grouped_by == "" or pd.isna(grouped_by):
                filtered_df = filtered_df[filtered_df['Grouped By'].isna() | (filtered_df['Grouped By'] == "")]
            else:
                filtered_df = filtered_df[filtered_df['Grouped By'] == grouped_by]
        
        if category:
            filtered_df = filtered_df[filtered_df['Category'] == category]
        
        # Pivot to get metrics as columns
        pivot_df = filtered_df.pivot_table(
            index=index_cols,
            columns='Metric Name', 
            values='Metric Value', 
            aggfunc='first'
        ).reset_index()
        pivot_df.columns.name = None  # Remove the 'Metric Name' label from columns
    else:
        # Count mode data - already in wide format, no filtering needed
        pivot_df = filtered_df.copy()

    return pivot_df


# 3. Primitive plotting utilities

def plot_to_img_html(fig):
    """Convert a matplotlib figure to a base64-encoded HTML img tag."""
    buf = BytesIO()
    fig.savefig(buf, format="png", bbox_inches="tight")
    plt.close(fig)
    buf.seek(0)
    img_b64 = base64.b64encode(buf.read()).decode("utf-8")
    return f'<img src="data:image/png;base64,{img_b64}" width="672"/>'


def metric_plot(df, x, y, hue, title, y_percent=False, stacked=False):
    """Create a styled barplot for a given metric."""
    fig, ax = plt.subplots(figsize=(10, 6))
    sns.set_style("whitegrid")
    
    plt.rcParams.update({
        'font.family': 'sans-serif',
        'font.sans-serif': ['Arial', 'DejaVu Sans', 'Liberation Sans', 'Bitstream Vera Sans', 'sans-serif'],
        'font.size': 11,
        'axes.titlesize': 13,
        'axes.labelsize': 11,
        'xtick.labelsize': 10,
        'ytick.labelsize': 10,
        'legend.fontsize': 10
    })
    
    plot_df = df.copy()
    
    # Clean the y column
    if y_percent:
        plot_df[y] = clean_percentage_column(plot_df[y])
    else:
        plot_df[y] = clean_numeric_column(plot_df[y])
    
    if stacked:
        pivot_df = plot_df.pivot_table(index=x, columns=hue, values=y, fill_value=0)
        pivot_df.plot(kind='bar', stacked=True, ax=ax, rot=90)
        ax.legend(bbox_to_anchor=(1.05, 0.5), loc='center left', title=hue)
    else:
        # Normalise the grouping column so captures with no pool assignment
        # (NaN) survive as an empty-string bucket. Without this, sorted()
        # over `.unique()` raises `TypeError: '<' not supported between
        # instances of 'str' and 'float'`; filling only inside the sort
        # would also silently drop those rows in the later
        # `plot_df[plot_df[x] == pool]` filter since NaN != "".
        plot_df[x] = plot_df[x].fillna("")
        pools = sorted(plot_df[x].unique())
        pool_data = {}
        for pool in pools:
            captures = sorted(plot_df[plot_df[x] == pool][hue].unique())
            pool_data[pool] = {c: plot_df[(plot_df[x]==pool)&(plot_df[hue]==c)][y].iloc[0] for c in captures}
        
        all_captures = list(df[hue].unique())
        capture_colors = {cap: f'C{i}' for i, cap in enumerate(all_captures)}
        bar_width = 0.6
        group_spacing = 1.0
        all_bars_data = []
        pool_centers = []
        current_x = 0
        
        for pool in pools:
            caps = list(pool_data[pool].keys())
            n = len(caps)
            if n == 1:
                cap = caps[0]
                all_bars_data.append((current_x, pool_data[pool][cap], capture_colors[cap], cap))
                pool_centers.append(current_x)
                current_x += group_spacing
            else:
                group_width = (n - 1) * bar_width
                start_x = current_x - group_width / 2
                for i, cap in enumerate(caps):
                    pos = start_x + i * bar_width
                    all_bars_data.append((pos, pool_data[pool][cap], capture_colors[cap], cap))
                pool_centers.append(current_x)
                current_x += max(group_width, bar_width) + group_spacing
        
        positions, values, colors, labels = zip(*all_bars_data)
        ax.bar(positions, values, bar_width, color=colors, alpha=0.8)
        ax.set_xticks(pool_centers)
        ax.set_xticklabels(pools, rotation=90)
        if len(set(labels))>1:
            handles = [plt.Rectangle((0,0),1,1,color=c,alpha=0.8) for _,c in capture_colors.items()]
            ax.legend(handles, capture_colors.keys(), bbox_to_anchor=(1.05,0.5), loc='center left', title=hue)
    
    if y_percent:
        ax.yaxis.set_major_formatter(plt.FuncFormatter(lambda val, _: f'{val:.0%}'))
    
    plt.xticks(rotation=90)
    plt.title(title)
    ax.set_xlabel(x)
    ax.set_ylabel(y)
    ax.grid(True, alpha=0.3)
    ax.set_facecolor('#fafafa')
    plt.tight_layout()
    return plot_to_img_html(fig)


# 4. HTML conversion helper

def df_to_html(df):
    """Render a DataFrame as an HTML table."""
    return df.to_html(classes="table table-sm table-striped small", index=False, border=0)


# 5. High-level section builder

def create_section_plots(df, index_cols, library_type, section_config, x_col, hue_col, category='Cells', grouped_by=None):
    """Create plots for a specific library type section and return plots + HTML table."""
    plots = {}
    # Prepare data subset
    plot_df = prepare_data_for_plotting(df, index_cols, library_type=library_type, category=category, grouped_by=grouped_by)
    
    if plot_df.empty:
        print(f"Warning: No data found for {library_type} - {category} - {grouped_by}")
        return plots, None
    print(f"Creating plots for {library_type} with {len(plot_df)} rows")
    print(f"Using x_col: {x_col}, hue_col: {hue_col}")
    
    # Generate each metric plot
    for metric_name, is_percent in section_config['metrics']:
        if metric_name in plot_df.columns:
            print(f"Generating plot for: {metric_name}")
            # Only stack cell count metrics (both multi and count mode names)
            is_stacked = metric_name in ['Cells', 'Estimated Number Of Cells']
            key = metric_name.replace(" ", "_").replace("%","pct").lower()
            plots[key] = metric_plot(plot_df, x_col, metric_name, hue_col, metric_name,
                                     y_percent=is_percent, stacked=is_stacked)
        else:
            print(f"Warning: Metric '{metric_name}' not found in data")
    
    # Build HTML table - use the actual column names that exist
    available_cols = [col for col in [hue_col, x_col] if col in plot_df.columns]
    metric_cols = [m for m, _ in section_config['metrics'] if m in plot_df.columns]
    table_cols = available_cols + metric_cols
    table_html = df_to_html(plot_df[table_cols]) if table_cols else df_to_html(plot_df)
    return plots, table_html
