# workflow/rules/predemux.smk

# Rules for pre-demultiplexing filtering
# The predemux workflow is used to filter out low-quality cells from the raw
# Cell Ranger output before demultiplexing. 
# It is broken into four rules:
#       1. Convert Cell Ranger output to Seurat object
#       2. Filter the Seurat object and save Cell Ranger formatted outputs
#       3. Identify the proportion of cells that would be discarded by each filter
#          at different thresholds
#       4. Generate a report summarising the filtering process and its impact on the data

import os 

rule predemux_convert_to_seurat:
    """
    Convert original Cell Ranger output (barcodes/features/matrix files) for a 
    capture into an RDS file containing a Seurat object. Also calculates and adds
    the mitochondrial percentage ('percent.mt') metadata for downstream filtering.
    """
    input:
        # Input does not depend on whether 'count' or 'multi' was run.
        # since both use the rule `restructure_counts`
        cr_dir = lambda wildcards: directory(os.path.dirname(rules.restructure_counts.output.filtered_bc.format(capture=wildcards.capture)))
    output:
        rds = temp(out_dir / "predemux" / "rds" / "{capture}.rds")
    log:
        log_dir / "predemux" / "pdmx_convert_seurat" / "{capture}.log"
    params:
        capture_id = "{capture}",
        mito_pattern = config['params']['predemux'].get("mito-pattern", "^MT-"),
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
    Apply user-defined filters (min genes, max mito %, min UMIs) from the config
    to the Seurat object for a capture. Saves the filtered data in Cell Ranger
    format (barcodes/features/matrix files) and saves the proportion of cells 
    discarded to a temporary text file (for downstream reporting).
    """
    input:
        rds = rules.predemux_convert_to_seurat.output.rds
    output:
        # Place predemux outputs in the same directory as the original Cell Ranger output
        cr_dir = directory(out_dir / "count/predemux/{capture}"),
        prop_txt = temp(out_dir / "predemux" / "qc" / "prop_discarded" / "{capture}.txt")
    log:
        log_dir /  "predemux" / "pdmx_filter" / "{capture}.log"
    params:
        capture_id = "{capture}",
        # Note: -1 is used to skip the filter
        min_genes = config['params']['predemux'].get("min-gene-count", -1),
        max_mito = config['params']['predemux'].get("max-mito", -1.0),
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
    For a capture's Seurat object, calculate the proportion of cells
    that would be discarded by each filter type (genes, mito, UMI) independently
    across a predefined range of thresholds. Saves results to CSV files for reporting.
    """
    input:
        rds = rules.predemux_convert_to_seurat.output.rds
    output:
        genes_csv = temp(out_dir / "predemux" / "qc" / "metrics" / "{capture}_genes.csv"),
        mito_csv = temp(out_dir / "predemux" / "qc" / "metrics" / "{capture}_mito.csv"),
        umi_csv = temp(out_dir / "predemux" / "qc" / "metrics" / "{capture}_umi.csv")
    log:
        log_dir /  "predemux" / "pdmx_metrics" / "{capture}.log"
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
    (from *_prop_discarded.txt) across all processed captures. Generates a
    HTML report summarising the impact of the chosen filters, along with plots
    showing average filter effects.
    """
    input:
        prop_txts = expand(rules.predemux_filter_seurat.output.prop_txt, capture=captures.index),
        gene_csvs = expand(rules.predemux_gather_qc_metrics.output.genes_csv, capture=captures.index),
        mito_csvs = expand(rules.predemux_gather_qc_metrics.output.mito_csv, capture=captures.index),
        umi_csvs = expand(rules.predemux_gather_qc_metrics.output.umi_csv, capture=captures.index)
    output:
        html = report_dir / "predemux" / "predemux_report.html",
        plot_genes = report_dir / "predemux" / "img" / "plot_genes.png",
        plot_mito = report_dir / "predemux" / "img" / "plot_mito.png",
        plot_umi = report_dir / "predemux" / "img" / "plot_umi.png"
    log:
        log_dir / "predemux" / "predemux_report.log"
    params:
        min_genes = config['params']['predemux'].get("min-gene-count", -1),
        max_mito = config['params']['predemux'].get("max-mito", -1.0),
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