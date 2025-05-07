#!/usr/bin/env python3
# Predemux Script 4: Aggregate metrics, generate plots, and create HTML report

import argparse
import pandas as pd
import numpy as np
import matplotlib.pyplot as plt
import logging
import os
from pathlib import Path

# --- Argument Parsing ---
parser = argparse.ArgumentParser(description="Generate predemux filtering report.")
parser.add_argument('--input-gene-csvs', nargs='+', required=True, help='List of input CSV files for gene filter metrics.')
parser.add_argument('--input-mito-csvs', nargs='+', required=True, help='List of input CSV files for mito filter metrics.')
parser.add_argument('--input-umi-csvs', nargs='+', required=True, help='List of input CSV files for UMI filter metrics.')
parser.add_argument('--input-prop-txts', nargs='+', required=True, help='List of input TXT files with proportion discarded.')
parser.add_argument('--config-min-genes', type=int, default=-1, help='User-configured min_genes threshold (-1 if disabled).')
parser.add_argument('--config-max-mito', type=float, default=-1.0, help='User-configured max_mito threshold (-1.0 if disabled).')
parser.add_argument('--config-min-umi', type=int, default=-1, help='User-configured min_umi threshold (-1 if disabled).')
parser.add_argument('--output-report-html', type=str, required=True, help='Path for the output HTML report file.')
parser.add_argument('--output-plot-genes', type=str, required=True, help='Path for the output genes filter plot PNG.')
parser.add_argument('--output-plot-mito', type=str, required=True, help='Path for the output mito filter plot PNG.')
parser.add_argument('--output-plot-umi', type=str, required=True, help='Path for the output UMI filter plot PNG.')
parser.add_argument('--log-file', type=str, default=None, help='Path to the log file.')

args = parser.parse_args()

# --- Logging Setup ---
log_format = '%(asctime)s - %(levelname)s - %(message)s'
if args.log_file:
    logging.basicConfig(filename=args.log_file, level=logging.INFO, format=log_format, filemode='w')
    # Also log to console
    console_handler = logging.StreamHandler()
    console_handler.setLevel(logging.INFO)
    formatter = logging.Formatter(log_format)
    console_handler.setFormatter(formatter)
    logging.getLogger().addHandler(console_handler)

else:
    logging.basicConfig(level=logging.INFO, format=log_format)

logging.info("Starting report generation script.")

# --- Helper Functions ---
def load_and_aggregate_metrics(csv_files, filter_name):
    """Loads multiple metric CSVs, concatenates, and calculates mean/std."""
    if not csv_files:
        logging.warning(f"No CSV files provided for filter: {filter_name}. Skipping aggregation.")
        return pd.DataFrame(columns=['threshold', 'mean_discarded', 'std_discarded'])

    all_dfs = []
    for f in csv_files:
        try:
            df = pd.read_csv(f)
            if not df.empty:
                all_dfs.append(df)
            else:
                logging.warning(f"Empty CSV file skipped: {f}")
        except Exception as e:
            logging.error(f"Error reading CSV {f}: {e}")
            continue # Skip this file

    if not all_dfs:
        logging.warning(f"No valid data found in CSVs for filter: {filter_name}.")
        return pd.DataFrame(columns=['threshold', 'mean_discarded', 'std_discarded'])

    combined_df = pd.concat(all_dfs, ignore_index=True)

    if combined_df.empty:
         logging.warning(f"Combined DataFrame is empty for filter: {filter_name}.")
         return pd.DataFrame(columns=['threshold', 'mean_discarded', 'std_discarded'])

    # Ensure correct types
    combined_df['threshold'] = pd.to_numeric(combined_df['threshold'], errors='coerce')
    combined_df['cumulative_prop_discarded'] = pd.to_numeric(combined_df['cumulative_prop_discarded'], errors='coerce')
    combined_df.dropna(subset=['threshold', 'cumulative_prop_discarded'], inplace=True)


    aggregated = combined_df.groupby('threshold')['cumulative_prop_discarded'].agg(['mean', 'std']).reset_index()
    aggregated.rename(columns={'mean': 'mean_discarded', 'std': 'std_discarded'}, inplace=True)
    aggregated['std_discarded'] = aggregated['std_discarded'].fillna(0) # Replace NaN std (e.g., single sample) with 0

    logging.info(f"Aggregated metrics for {filter_name} across {len(all_dfs)} samples.")
    return aggregated

def create_filter_plot(agg_data, config_threshold, title, xlabel, ylabel, output_path, filter_type):
    """Generates and saves a plot for a single filter."""
    # TODO: Improve visual appearance of plots (more y-axis ticks, better formatting, etc.)
    if agg_data.empty:
        logging.warning(f"No data to plot for {title}. Creating empty plot.")
        fig, ax = plt.subplots(figsize=(8, 5))
        ax.text(0.5, 0.5, 'No data available', horizontalalignment='center', verticalalignment='center', transform=ax.transAxes)
        ax.set_title(title)
        plt.tight_layout()
        plt.savefig(output_path, dpi=100)
        plt.close(fig)
        return None # Return None to indicate no valid threshold value

    plt.style.use('seaborn-v0_8-whitegrid')
    fig, ax = plt.subplots(figsize=(8, 5))

    # Sort by threshold for correct line plotting
    agg_data = agg_data.sort_values('threshold')

    ax.errorbar(agg_data['threshold'], agg_data['mean_discarded'] * 100,
                yerr=agg_data['std_discarded'] * 100, fmt='-o', capsize=3, alpha=0.8,
                label='Mean ± SD Discarded')

    # Add vertical line for the filter threshold in the config
    config_val_text = "N/A"
    mean_discarded_at_config = None
    if (filter_type == "min" and config_threshold != -1) or \
       (filter_type == "max" and config_threshold != -1.0):

        ax.axvline(x=config_threshold, color='red', linestyle='--', linewidth=1.5, label=f'Chosen Threshold ({config_threshold})')

        # Interpolate the mean discarded percentage at the config threshold
        try:
            mean_discarded_at_config = np.interp(config_threshold, agg_data['threshold'], agg_data['mean_discarded']) * 100
            config_val_text = f"{mean_discarded_at_config:.1f}%"
            # Add text annotation slightly to the right of the line
            ax.text(config_threshold, ax.get_ylim()[1]*0.9, f'~{config_val_text} discarded', color='red',
                    ha='left', va='top', rotation=0, fontsize=9,
                    bbox=dict(boxstyle='round,pad=0.3', fc='white', alpha=0.7, ec='none')) # Use bbox for better visibility
        except Exception as e:
             logging.warning(f"Could not interpolate value for threshold {config_threshold} in {title}: {e}")
             config_val_text = "Error"


    ax.set_xlabel(xlabel)
    ax.set_ylabel(ylabel)
    ax.set_title(title)
    ax.legend(loc='best', fontsize='small') # Adjust legend position and size
    ax.set_ylim(bottom=max(-5, ax.get_ylim()[0])) # Ensure y-axis starts near 0 but allows negative if error bars go below
    ax.set_xlim(left=min(agg_data['threshold']) - (max(agg_data['threshold']) - min(agg_data['threshold']))*0.05,
                 right=max(agg_data['threshold']) + (max(agg_data['threshold']) - min(agg_data['threshold']))*0.05) # Add padding to x-axis


    plt.tight_layout()
    plt.savefig(output_path, dpi=100)
    logging.info(f"Saved plot: {output_path}")
    plt.close(fig)
    return mean_discarded_at_config # Return the interpolated value for the report


def read_proportion_discarded(txt_files):
    """Reads proportion discarded from each capture (in txt files)."""
    proportions = {}
    if not txt_files:
        logging.warning("No proportion discarded TXT files provided.")
        return pd.DataFrame(columns=['capture_id', 'prop_discarded'])

    for f_path in txt_files:
        try:
            p = Path(f_path)
            # Infer capture_id from filename (assuming format like 'capture_id.proportion.txt')
            # Adjust this logic if your filenames are different
            capture_id = p.name.split('.')[0]
            with open(f_path, 'r') as f:
                value = float(f.readline().strip())
                proportions[capture_id] = value
        except Exception as e:
            logging.error(f"Error reading proportion file {f_path}: {e}")
            continue # Skip this file

    if not proportions:
        logging.warning("No valid data found in proportion TXT files.")
        return pd.DataFrame(columns=['capture_id', 'prop_discarded'])

    prop_df = pd.DataFrame(list(proportions.items()), columns=['capture_id', 'prop_discarded'])
    logging.info(f"Read proportion discarded data for {len(prop_df)} samples.")
    return prop_df


# --- Main Execution ---
try:
    # 1. Aggregate metrics for each filter
    logging.info("Aggregating filter metrics...")
    gene_agg = load_and_aggregate_metrics(args.input_gene_csvs, "Min Genes")
    mito_agg = load_and_aggregate_metrics(args.input_mito_csvs, "Max Mito")
    umi_agg = load_and_aggregate_metrics(args.input_umi_csvs, "Min UMI")

    # 2. Generate Plots
    logging.info("Generating filter plots...")
    discard_at_config_genes = create_filter_plot(gene_agg, args.config_min_genes, 'Impact of Minimum Genes Filter', 'Min Genes per Cell Threshold', 'Cumulative % Cells Discarded (Mean ± SD)', args.output_plot_genes, "min")
    # Mito thresholds are plotted in decreasing order to show increasing stringency left-to-right
    discard_at_config_mito = create_filter_plot(mito_agg, args.config_max_mito, 'Impact of Max Mitochondrial % Filter', 'Max Mito % Threshold', 'Cumulative % Cells Discarded (Mean ± SD)', args.output_plot_mito, "max")
    discard_at_config_umi = create_filter_plot(umi_agg, args.config_min_umi, 'Impact of Minimum UMI Filter', 'Min UMIs per Cell Threshold', 'Cumulative % Cells Discarded (Mean ± SD)', args.output_plot_umi, "min")

    # For cases where the filter was not applied
    def fmt(pct):
        return f"{pct:.1f}%" if pct is not None else "N/A"

    discard_at_config_genes = fmt(discard_at_config_genes)
    discard_at_config_mito  = fmt(discard_at_config_mito)
    discard_at_config_umi   = fmt(discard_at_config_umi)

    # 3. Process overall proportion discarded
    logging.info("Processing overall proportion discarded...")
    prop_df = read_proportion_discarded(args.input_prop_txts)
    num_samples = len(prop_df)

    overall_mean_discarded = np.nanmean(prop_df['prop_discarded']) * 100 if num_samples > 0 else 0
    overall_std_discarded = np.nanstd(prop_df['prop_discarded']) * 100 if num_samples > 0 else 0

    # 4. Identify high discard samples
    high_discard_threshold = np.nanpercentile(prop_df['prop_discarded'], 90) if num_samples > 0 else -1
    high_discard_samples = prop_df[prop_df['prop_discarded'] >= high_discard_threshold].sort_values('prop_discarded', ascending=False) if num_samples > 0 else pd.DataFrame(columns=['capture_id', 'prop_discarded'])

    # Convert proportions to percentage strings for the table
    prop_df['prop_discarded_pct_str'] = (prop_df['prop_discarded'] * 100).map('{:.2f}%'.format)
    high_discard_samples['prop_discarded_pct_str'] = (high_discard_samples['prop_discarded'] * 100).map('{:.2f}%'.format)

    # 5. Generate HTML Report
    logging.info("Generating HTML report...")

    # Get relative paths for images in HTML
    report_dir = Path(args.output_report_html).parent
    try:
        rel_plot_genes = os.path.relpath(args.output_plot_genes, report_dir)
        rel_plot_mito = os.path.relpath(args.output_plot_mito, report_dir)
        rel_plot_umi = os.path.relpath(args.output_plot_umi, report_dir)
    except ValueError: # Happens if paths are on different drives on Windows
         logging.warning("Could not create relative paths for plots. Using absolute paths.")
         rel_plot_genes = args.output_plot_genes
         rel_plot_mito = args.output_plot_mito
         rel_plot_umi = args.output_plot_umi

# TODO: Customise report formatting
    html_content = f"""
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>scRNA-seq Filtering Report</title>
    <style>
        body {{ font-family: sans-serif; margin: 20px; }}
        h1, h2, h3 {{ color: #333; }}
        table {{ border-collapse: collapse; width: auto; margin-bottom: 20px; }}
        th, td {{ border: 1px solid #ddd; padding: 8px; text-align: left; }}
        th {{ background-color: #f2f2f2; }}
        .container {{ max-width: 900px; margin: auto; }}
        .summary-box {{ background-color: #eef; padding: 15px; border: 1px solid #ccd; margin-bottom: 20px; }}
        .plot-container {{ margin-bottom: 30px; text-align: center; }}
        img {{ max-width: 100%; height: auto; border: 1px solid #ccc; }}
        .code {{ font-family: monospace; background-color: #eee; padding: 2px 5px; }}
    </style>
</head>
<body>
    <div class="container">
        <h1>scRNA-seq Filtering Report</h1>

        <div class="summary-box">
            <h2>Summary</h2>
            <p><strong>Number of samples processed:</strong> {num_samples}</p>
            <h3>User-Defined Filter Thresholds:</h3>
            <ul>
                <li>Minimum Genes per Cell (<span class="code">nFeature_RNA</span>): {'Disabled' if args.config_min_genes == -1 else args.config_min_genes}</li>
                <li>Maximum Mitochondrial % (<span class="code">percent.mt</span>): {'Disabled' if args.config_max_mito == -1.0 else f'{args.config_max_mito:.1f}%'}</li>
                <li>Minimum UMIs per Cell (<span class="code">nCount_RNA</span>): {'Disabled' if args.config_min_umi == -1 else args.config_min_umi}</li>
            </ul>
            <p><strong>Overall % of cells discarded (Mean ± SD):</strong> {overall_mean_discarded:.2f}% ± {overall_std_discarded:.2f}%</p>
             <p><small>Note: The 'Overall % discarded' considers the combined effect of all enabled filters.</small></p>
        </div>

        <h2>Impact of Individual Filters</h2>
        <p>These plots show the average cumulative percentage of cells that would be discarded by each filter *independently* across a range of thresholds. The red dashed line indicates the threshold chosen in the configuration.</p>

        <div class="plot-container">
            <h3>Minimum Genes per Cell Filter</h3>
            <img src="{rel_plot_genes}" alt="Minimum Genes Filter Plot">
             <p><small>At the chosen threshold ({'Disabled' if args.config_min_genes == -1 else args.config_min_genes}), this filter alone discarded ~{discard_at_config_genes} of cells on average.</small></p>
        </div>

        <div class="plot-container">
            <h3>Maximum Mitochondrial % Filter</h3>
            <img src="{rel_plot_mito}" alt="Maximum Mito Filter Plot">
             <p><small>At the chosen threshold ({'Disabled' if args.config_max_mito == -1.0 else f'{args.config_max_mito:.1f}%'}), this filter alone discarded ~{discard_at_config_mito} of cells on average.</small></p>
        </div>

        <div class="plot-container">
            <h3>Minimum UMIs per Cell Filter</h3>
            <img src="{rel_plot_umi}" alt="Minimum UMI Filter Plot">
             <p><small>At the chosen threshold ({'Disabled' if args.config_min_umi == -1 else args.config_min_umi}), this filter alone discarded ~{discard_at_config_umi} of cells on average.</small></p>
        </div>


        <h2>Samples with High Proportion of Cells Discarded</h2>
        <p>Samples listed below had a total percentage of cells discarded (by the combined filters) in the 90th percentile or higher (≥ {high_discard_threshold*100:.2f}%).</p>
        {high_discard_samples[['capture_id', 'prop_discarded_pct_str']].rename(columns={'prop_discarded_pct_str': '% Discarded'}).to_html(index=False, classes='small-table') if not high_discard_samples.empty else '<p>No samples identified in the top 90th percentile for discarded cells.</p>'}

        <h2>Reference: % Cells Discarded per Sample</h2>
        <p>The following table lists the total percentage of cells discarded for each sample using the combined filter settings.</p>
        {prop_df[['capture_id', 'prop_discarded_pct_str']].rename(columns={'prop_discarded_pct_str': '% Discarded'}).sort_values('capture_id').to_html(index=False, classes='full-table') if not prop_df.empty else '<p>No proportion data available.</p>'}

    </div>
</body>
</html>
"""

    # Write HTML report to output directory
    with open(args.output_report_html, 'w') as f_html:
        f_html.write(html_content)
    logging.info(f"Successfully generated HTML report: {args.output_report_html}")

except Exception as e:
    logging.error(f"An error occurred during script execution: {e}", exc_info=True)
    raise # Re-raise the exception to notify Snakemake of failure

logging.info("Report generation script finished.")