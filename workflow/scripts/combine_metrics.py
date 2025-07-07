#!/usr/bin/env python3
"""
Combine individual capture CSV files into a single summary CSV file.
This script is designed to work with Snakemake workflow.
"""
import pandas as pd
from pathlib import Path
import os
import sys

log = open(snakemake.log[0], "w")
sys.stdout = sys.stderr = log

# Get Snakemake inputs/outputs
captures_csv = snakemake.input.captures
output_csv = snakemake.output.combined_csv

print(f"Input captures file: {captures_csv}")
print(f"Output CSV: {output_csv}")

# Read the config file to get capture and pool information
config_df = pd.read_csv(captures_csv)

# The input CSV files are in the results directory under summary/metrics/
# We can get the base results directory from the snakemake config
input_dir = Path(snakemake.config['outs']['results']) / "summary" / "metrics"
print(f"Looking for input files in: {input_dir}")

# Create output directory if it doesn't exist
os.makedirs(Path(output_csv).parent, exist_ok=True)

# Expecting columns: capture, pool in the captures CSV
tables = []
for _, row in config_df.iterrows():
    capture = row['capture']
    pool = row['pool']
    
    # Look for the individual capture CSV file
    input_csv = input_dir / f"{capture}.csv"
    
    if input_csv.exists():
        df = pd.read_csv(input_csv)
        df["Capture"] = capture
        df["Pool"] = pool
        tables.append(df)
    else:
        print(f"Warning: {input_csv} not found, skipping {capture}")

if tables:
    # Combine all tables
    combined = pd.concat(tables, ignore_index=True)
    
    # Write out the combined CSV with capture and pool columns
    combined.to_csv(output_csv, index=False)
    print(f"Combined {len(tables)} capture files into {output_csv}")
else:
    print("No valid capture CSV files found")


log.close()