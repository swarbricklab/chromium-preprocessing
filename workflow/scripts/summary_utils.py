#!/usr/bin/env python3
"""
Utility functions for generating summary report plots and tables.
"""
import pandas as pd
import matplotlib.pyplot as plt
import seaborn as sns
import numpy as np
import base64
from io import BytesIO

def df_to_html(df):
    """Render a DataFrame as an HTML table."""
    return df.to_html(classes="table table-sm table-striped small", index=False, border=0)

def plot_to_img_html(fig):
    """Convert a matplotlib figure to a base64-encoded HTML img tag."""
    buf = BytesIO()
    fig.savefig(buf, format="png", bbox_inches="tight")
    plt.close(fig)
    buf.seek(0)
    img_b64 = base64.b64encode(buf.read()).decode("utf-8")
    return f'<img src="data:image/png;base64,{img_b64}" width="672"/>'

def clean_numeric_column(series):
    """Clean numeric columns by removing commas and converting to float."""
    if series.dtype == 'object':  # String data
        return series.str.replace(',', '').astype(float)
    else:  # Already numeric
        return series.astype(float)

def clean_percentage_column(series):
    """Clean percentage columns by removing % and converting to float (0-1 scale)."""
    if series.dtype == 'object':  # String data like "98.2%"
        return series.str.replace('%', '').astype(float) / 100
    else:  # Already numeric (assume it's already in 0-1 scale)
        return series.astype(float)

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
    
    # Create a copy of the dataframe for plotting
    plot_df = df.copy()
    
    # Clean the y column based on its data type
    if y_percent:
        plot_df[y] = clean_percentage_column(plot_df[y])
    else:
        plot_df[y] = clean_numeric_column(plot_df[y])
    
    if stacked:
        # Create stacked bar chart
        pivot_df = plot_df.pivot_table(index=x, columns=hue, values=y, fill_value=0)
        pivot_df.plot(kind='bar', stacked=True, ax=ax, rot=90)
        ax.legend(bbox_to_anchor=(1.05, 0.5), loc='center left', title=hue)
    else:
        # Use custom bar positioning for proper centering under pool labels
        pools = sorted(plot_df[x].unique())
        
        # Group data by pool
        pool_data = {}
        for pool in pools:
            pool_captures = sorted(plot_df[plot_df[x] == pool][hue].unique())
            pool_data[pool] = {}
            for capture in pool_captures:
                capture_data = plot_df[(plot_df[x] == pool) & (plot_df[hue] == capture)]
                if len(capture_data) > 0:
                    pool_data[pool][capture] = capture_data[y].iloc[0]
        
        # For grouped bars, assign consistent colors to captures across all pools
        all_captures = list(df[hue].unique())
        capture_colors = {capture: f'C{i}' for i, capture in enumerate(all_captures)}
        
        # Calculate positions for proper centering
        bar_width = 0.6
        group_spacing = 1.0
        all_bars_data = []
        pool_centers = []
        current_x = 0
        
        for pool_idx, pool in enumerate(pools):
            captures = list(pool_data[pool].keys())
            n_captures = len(captures)
            
            if n_captures == 1:
                # Single capture - center it
                capture = captures[0]
                value = pool_data[pool][capture]
                color = capture_colors[capture]
                all_bars_data.append((current_x, value, color, capture))
                pool_centers.append(current_x)
                current_x += group_spacing
            else:
                # Multiple captures - space them symmetrically around center
                group_width = (n_captures - 1) * bar_width
                start_x = current_x - group_width / 2
                
                for i, capture in enumerate(captures):
                    pos = start_x + i * bar_width
                    value = pool_data[pool][capture]
                    color = capture_colors[capture]
                    all_bars_data.append((pos, value, color, capture))
                
                pool_centers.append(current_x)
                current_x += max(group_width, bar_width) + group_spacing
        
        # Plot all bars
        positions, values, bar_colors, labels = zip(*all_bars_data)
        bars = ax.bar(positions, values, bar_width, color=bar_colors, alpha=0.8)
        
        # Set pool labels at group centers
        ax.set_xticks(pool_centers)
        ax.set_xticklabels(pools, rotation=90)
        
        # Create legend with unique captures
        unique_captures = sorted(list(set(label for _, _, _, label in all_bars_data)))
        if len(unique_captures) > 1:
            legend_handles = [plt.Rectangle((0,0),1,1, color=f'C{i}', alpha=0.8) 
                            for i in range(len(unique_captures))]
            ax.legend(legend_handles, unique_captures, 
                     bbox_to_anchor=(1.05, 0.5), loc='center left', title=hue)
    
    # Format percentage axis if needed
    if y_percent:
        ax.yaxis.set_major_formatter(plt.FuncFormatter(lambda y, _: f'{y:.0%}'))
    
    plt.xticks(rotation=90)
    plt.title(title, fontweight='normal', color='#2c3e50')
    ax.set_xlabel(x, color='#2c3e50')
    ax.set_ylabel(y, color='#2c3e50')
    
    # Match the grid and background styling
    ax.grid(True, alpha=0.3)
    ax.set_facecolor('#fafafa')
    
    plt.tight_layout()
    return plot_to_img_html(fig)
    
    # Format percentage axis if needed
    if y_percent:
        ax.yaxis.set_major_formatter(plt.FuncFormatter(lambda y, _: f'{y:.0%}'))
    
    plt.xticks(rotation=90)
    plt.title(title, fontweight='normal', color='#2c3e50')
    ax.set_xlabel(x, color='#2c3e50')
    ax.set_ylabel(y, color='#2c3e50')
    
    # Match the grid and background styling
    ax.grid(True, alpha=0.3)
    ax.set_facecolor('#fafafa')
    
    plt.tight_layout()
    return plot_to_img_html(fig)
