# workflow/rules/predemux.smk
# Rules for pre-demultiplexing filtering

# TODO: Check if imports needed
import pandas as pd
from pathlib import Path
import os 

# --- Workflow Rules ---
rule predemux_convert_to_seurat:
    """
    Convert original Cell Ranger output for a capture
    into an RDS file containing a Seurat object. Also calculates and adds
    the mitochondrial percentage ('percent.mt') metadata.
    """
    input:
        # Input does not depend on whether 'count' or 'multi' was run.
        # since both use the rule `restructure_counts`
        cr_dir = lambda wildcards: directory(os.path.dirname(rules.restructure_counts.output.filtered_bc.format(capture=wildcards.capture)))
    output:
        # Place predemux outputs in a dedicated subdirectory
        # TODO: Make temporary
        rds = out_dir / "predemux" / "rds" / "{capture}.rds"
    log:
        # TODO: Create an overarching Predemux log directory
        log_dir / "predemux_convert" / "{capture}.log"
    params:
        capture_id = "{capture}",
        # TODO: Add ^MT- to config
        mito_pattern = config['params']['predemux'].get("mito_pattern", "^MT-"),
        r_script_path = "workflow/scripts/pdmx_convert_seurat.R"
    conda:
        "../envs/predemux.yaml"
    shell:
        """
        Rscript "{params.r_script_path}" \
            --input-dir "{input.cr_dir}" \
            --output-rds "{output.rds}" \
            --mito-pattern '{params.mito_pattern}' \
            --capture-id "{params.capture_id}" \
            --log-file "{log}" > "{log}" 2>&1
        """

rule predemux_filter_seurat:
    """
    Apply user-defined filters (min genes, max mito %, min UMIs from config)
    to the Seurat object for a capture. Saves the filtered data in Cell Ranger v3
    format and outputs the proportion of cells discarded to a text file.
    """
    input:
        rds = rules.predemux_convert_to_seurat.output.rds
    output:
        cr_dir = directory(out_dir / "predemux" / "filtered_cr" / "{capture}"),
        # Save proportion of cells discarded after filtering (for later report)
        prop_txt = out_dir / "predemux" / "qc" / "prop_discarded" / "{capture}.txt"
    log:
        log_dir / "predemux_filter" / "{capture}.log"
    params:
        capture_id = "{capture}",
        # -1 if missing (skip filter)
        min_genes = config['params']['predemux'].get("min-gene-count", -1),
        # TODO: Fix inconsistency between percentage input and decimal input
        max_mito = lambda wc: float(config['params']['predemux'].get("max-mito", -1.0)) * 100.0 if str(config['params']['predemux'].get("max-mito", "-1.0")).replace('.', '', 1).lstrip('-').isdigit() else -1.0,
        min_umi = config['params']['predemux'].get("min-umi-count", -1),
        r_script_path = "workflow/scripts/pdmx_filter.R"
    conda:
        "../envs/predemux.yaml"
    shell:
        """
        Rscript "{params.r_script_path}" \
            --input-rds "{input.rds}" \
            --output-dir "{output.cr_dir}" \
            --output-txt "{output.prop_txt}" \
            --min-genes "{params.min_genes}" \
            --max-mito "{params.max_mito}" \
            --min-umi "{params.min_umi}" \
            --capture-id "{params.capture_id}" \
            --log-file "{log}" > "{log}" 2>&1
        """

rule predemux_gather_qc_metrics:
    """
    For a capture's Seurat object, calculate the cumulative proportion of cells
    that would be discarded by each filter type (genes, mito, UMI) independently
    across a predefined range of thresholds. Saves results to CSV files for reporting.
    """
    input:
        rds = rules.predemux_convert_to_seurat.output.rds
    output:
        genes_csv = out_dir / "predemux" / "qc" / "metrics" / "{capture}_genes.csv",
        mito_csv = out_dir / "predemux" / "qc" / "metrics" / "{capture}_mito.csv",
        umi_csv = out_dir / "predemux" / "qc" / "metrics" / "{capture}_umi.csv"
    log:
        log_dir / "predemux_metrics" / "{capture}.log"
    params:
        capture_id = "{capture}",
        r_script_path = "workflow/scripts/pdmx_metrics.R"
    conda:
        "../envs/predemux.yaml"
    shell:
        """
        Rscript "{params.r_script_path}" \
            --input-rds "{input.rds}" \
            --output-csv-genes "{output.genes_csv}" \
            --output-csv-mito "{output.mito_csv}" \
            --output-csv-umi "{output.umi_csv}" \
            --capture-id "{params.capture_id}" \
            --log-file "{log}" > "{log}" 2>&1
        """

rule predemux_generate_report:
    """
    Aggregate filtering metrics (from *_metrics.csv) and cell discarded proportions
    (from *_prop_discarded.txt) across all processed captures. Generates an
    HTML report summarising the impact of the chosen filters, along with plots
    showing average filter effects.
    """
    input:
        # Aggregate all necessary files
        prop_txts = expand(rules.predemux_filter_seurat.output.prop_txt, capture=captures.index),
        gene_csvs = expand(rules.predemux_gather_qc_metrics.output.genes_csv, capture=captures.index),
        mito_csvs = expand(rules.predemux_gather_qc_metrics.output.mito_csv, capture=captures.index),
        umi_csvs = expand(rules.predemux_gather_qc_metrics.output.umi_csv, capture=captures.index)
    output:
        html = out_dir / "predemux" / "qc" / "report.html",
        plot_genes = out_dir / "predemux" / "qc" / "plot_genes.png",
        plot_mito = out_dir / "predemux" / "qc" / "plot_mito.png",
        plot_umi = out_dir / "predemux" / "qc" / "plot_umi.png"
    log:
        log_dir / "predemux_report.log"
    params:
        # Re-obtain user params from config
        min_genes = config['params']['predemux'].get("min-gene-count", -1),
        max_mito = lambda wc: float(config['params']['predemux'].get("max-mito", -1.0)) * 100.0 if str(config['params']['predemux'].get("max-mito", "-1.0")).replace('.', '', 1).lstrip('-').isdigit() else -1.0,
        min_umi = config['params']['predemux'].get("min-umi-count", -1),
        py_script_path = "workflow/scripts/pdmx_report.py"
    conda:
        "../envs/predemux.yaml"
    shell:
         """
         python "{params.py_script_path}" \
             --input-prop-txts {input.prop_txts} \
             --input-gene-csvs {input.gene_csvs} \
             --input-mito-csvs {input.mito_csvs} \
             --input-umi-csvs {input.umi_csvs} \
             --config-min-genes "{params.min_genes}" \
             --config-max-mito "{params.max_mito}" \
             --config-min-umi "{params.min_umi}" \
             --output-report-html "{output.html}" \
             --output-plot-genes "{output.plot_genes}" \
             --output-plot-mito "{output.plot_mito}" \
             --output-plot-umi "{output.plot_umi}" \
             --log-file "{log}" > "{log}" 2>&1
         """