#!/usr/bin/env python3
# Generate a summary report for Chromium-Preprocessing metrics `summary/metrics/`
import pandas as pd
import matplotlib.pyplot as plt
import seaborn as sns
from jinja2 import Environment, FileSystemLoader, select_autoescape
import os
import base64
from io import BytesIO
import datetime

# Helper to render a DataFrame as HTML table
def df_to_html(df):
    return df.to_html(classes="table table-sm table-striped small", index=False, border=0)

# Helper to plot and return as base64-encoded <img>
def plot_to_img(fig):
    buf = BytesIO()
    fig.savefig(buf, format="png", bbox_inches="tight")
    plt.close(fig)
    buf.seek(0)
    img_b64 = base64.b64encode(buf.read()).decode("utf-8")
    return f'<img src="data:image/png;base64,{img_b64}" width="672"/>'

# Load data
results_dir = "test/results/cellranger/count_test/"
ge = pd.read_csv(results_dir + "summary/metrics/gene_expression_cell_summary.csv")
# lib_metrics = pd.read_csv(results_dir + "summary/metrics/library_summary.csv")
# capture_pool = pd.read_csv("config/tests/count/captures.csv")
script_dir = os.path.dirname(os.path.abspath(__file__))
# --- Jinja2 HTML template ---
env = Environment(
    loader=FileSystemLoader(script_dir),
    autoescape=select_autoescape(['html'])
)
template = env.get_template("summary_template.html")

fig = plt.figure(figsize=(10,6))
sns.barplot(data=ge, x='Pool', y='Estimated Number of Cells', hue='Capture')
plt.xticks(rotation=90)
plt.title('Cells per capture pool')
cells_per_capture_pool_png = plot_to_img(fig)

fig = plt.figure(figsize=(10,6))
sns.barplot(data=ge, x='Pool', y='Reads Mapped Confidently to Genome', hue='Capture')
plt.xticks(rotation=90)
plt.title('Reads Mapped Confidently to Genome')
confidently_mapped_reads_png = plot_to_img(fig)

fig = plt.figure(figsize=(10,6))
sns.barplot(data=ge, x='Pool', y='Median UMI Counts per Cell', hue='Capture')
plt.xticks(rotation=90)
plt.title('Median UMI Counts per Cell')
median_umi_counts_png = plot_to_img(fig)

fig = plt.figure(figsize=(10,6))
sns.barplot(data=ge, x='Pool', y='Median Genes per Cell', hue='Capture')
plt.xticks(rotation=90)
plt.title('Median Genes per Cell')
median_genes_per_cell_png = plot_to_img(fig)

fig = plt.figure(figsize=(10,6))
sns.barplot(data=ge, x='Pool', y='Mean Reads per Cell', hue='Capture')
plt.xticks(rotation=90)
plt.title('Mean Reads per Cell')
mean_reads_per_cell_png = plot_to_img(fig)

fig = plt.figure(figsize=(10,6))
sns.barplot(data=ge, x='Pool', y='Total Genes Detected', hue='Capture')
plt.xticks(rotation=90)
plt.title('Total Genes Detected')
total_genes_detected_png = plot_to_img(fig)

# --- Render tables as HTML ---
cols = [
    'Capture',
    'Pool',
    'Estimated Number of Cells',
    'Reads Mapped Confidently to Genome',
    'Median UMI Counts per Cell',
    'Median Genes per Cell',
    'Mean Reads per Cell',
    'Total Genes Detected'
]
ge_table = df_to_html(ge[cols])
# lib_table = df_to_html(lib_metrics)

# --- Render HTML report ---
html_out = template.render(
    ge_table=ge_table,
    # lib_table=lib_table,
    cells_per_capture_pool_png=cells_per_capture_pool_png,
    confidently_mapped_reads_png=confidently_mapped_reads_png,
    median_umi_counts_png=median_umi_counts_png,
    median_genes_per_cell_png=median_genes_per_cell_png,
    mean_reads_per_cell_png=mean_reads_per_cell_png,
    total_genes_detected_png=total_genes_detected_png,
    timestamp  = datetime.datetime.now().isoformat(timespec="seconds")
)

os.makedirs(results_dir + "reports/cellranger/", exist_ok=True)
with open(results_dir + "reports/cellranger/chromium_summary.html", "w") as f:
    f.write(html_out)

print(f"Report generated: {results_dir}reports/cellranger/chromium_summary.html")
