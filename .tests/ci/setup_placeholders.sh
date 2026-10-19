#!/bin/bash
# Touch empty placeholder inputs so `snakemake -n` can build the full DAG (count
# and multi modes) in CI without any real data. Mirrors config/tests/{count,multi}.
set -eu
# references (checked with os.path.exists at parse time) — dirs
mkdir -p resources/transcriptomes/refdata-gex-GRCh38-2020-A
mkdir -p resources/vdj/refdata-cellranger-vdj-GRCh38-alts-ensembl-7.1.0
# report resources — fixed named files
mkdir -p resources/report
touch resources/report/base_template.html resources/report/chromium_styles.css \
      resources/report/summary_template.html resources/report/swarbricklablogo.png
# fastq dirs from the test libraries.csv (count: tiny_pbmc; multi: tiny_pbmc2)
mkdir -p test/data/tiny_pbmc/GE/PBMC_001 test/data/tiny_pbmc/GE/PBMC_002 test/data/tiny_pbmc/GE/PBMC_003
for cap in PBMC2_a PBMC2_b; do
  mkdir -p "test/data/tiny_pbmc2/$cap/FB-AB" "test/data/tiny_pbmc2/$cap/GE5" "test/data/tiny_pbmc2/$cap/VDJ-T"
done
echo "placeholders touched"
