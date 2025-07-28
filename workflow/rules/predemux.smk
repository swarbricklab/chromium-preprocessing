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

rule predemux_convert_to_seurat:
    """
    Convert original Cell Ranger output (filtered h5 file) for a
    capture into an RDS file containing a Seurat object. Also calculates and adds
    the mitochondrial percentage ('percent.mt') metadata for downstream filtering.
    """
    input:
        # Input does not depend on whether 'count' or 'multi' was run.
        # since both use the rule `restructure_h5`
        filtered_mat = rules.restructure_h5.output.filtered_mat
    output:
        rds = temp(out_dir/"predemux/rds/{capture}.rds")
    log:
        log_dir/"predemux/pdmx_convert_seurat/{capture}.log"
    params:
        mito_pattern = config['params']['predemux']["mito-pattern"]
    conda:
        "../envs/predemux.yaml"
    script:
        "../scripts/pdmx_convert_seurat.R"

rule predemux_filter_seurat:
    """
    Apply user-defined filters (min genes, max mito %, min UMIs) from the config
    to the Seurat object for a capture. Saves the filtered data in Cell Ranger
    format (barcodes/features/matrix files) and saves the proportion of cells
    discarded to a temporary text file (for downstream reporting). After running, 
    features.tsv.gz is removed (replaced in rule `copy_original_features`).
    """
    input:
        rds = rules.predemux_convert_to_seurat.output.rds
    output:
        # For compatability with features.tsv.gz replacement, we specify exact files
        # rather than the directory function and output directory, 
        # and remove the features.tsv.gz file from the output
        barcodes = out_dir/"count/predemux/{capture}/barcodes.tsv.gz",
        matrix = out_dir/"count/predemux/{capture}/matrix.mtx.gz",
        filter_metrics = temp(out_dir/"predemux/qc/discarded_metrics/{capture}.csv")
    log:
        log_dir/"predemux/pdmx_filter/{capture}.log"
    params:
        min_genes = config['params']['predemux']["min-gene-count"],
        max_mito = config['params']['predemux']["max-mito"],
        min_umi = config['params']['predemux']["min-umi-count"],
    conda:
        "../envs/predemux.yaml"
    script:
        "../scripts/pdmx_filter.R"

rule predemux_gather_qc_metrics:
    """
    For a capture's Seurat object, calculate the proportion of cells
    that would be discarded by each filter type (genes, mito, UMI) independently
    across a predefined range of thresholds. Saves results to CSV files for reporting.
    """
    input:
        rds = rules.predemux_convert_to_seurat.output.rds
    output:
        genes_csv = temp(out_dir/"predemux/qc/metrics/{capture}_genes.csv"),
        mito_csv = temp(out_dir/"predemux/qc/metrics/{capture}_mito.csv"),
        umi_csv = temp(out_dir/"predemux/qc/metrics/{capture}_umi.csv")
    log:
        log_dir/"predemux/pdmx_metrics/{capture}.log"
    conda:
        "../envs/predemux.yaml"
    script:
        "../scripts/pdmx_metrics.R"

rule predemux_generate_report:
    """
    Aggregate filtering metrics (from *_metrics.csv) and cell discarded proportions
    (from *_prop_discarded.txt) across all processed captures. Generates a
    HTML report summarising the impact of the chosen filters, along with plots
    showing average filter effects.
    """
    input:
        filter_stats_csvs = expand(rules.predemux_filter_seurat.output.filter_metrics, capture=captures.index),
        gene_csvs = expand(rules.predemux_gather_qc_metrics.output.genes_csv, capture=captures.index),
        mito_csvs = expand(rules.predemux_gather_qc_metrics.output.mito_csv, capture=captures.index),
        umi_csvs = expand(rules.predemux_gather_qc_metrics.output.umi_csv, capture=captures.index)
    output:
        html = report_dir/"predemux/predemux_report.html",
        plot_genes = report_dir/"predemux/img/plot_genes.png",
        plot_mito = report_dir/"predemux/img/plot_mito.png",
        plot_umi = report_dir/"predemux/img/plot_umi.png"
    log:
        log_dir/"predemux/predemux_report.log"
    params:
        min_genes = config['params']['predemux']["min-gene-count"],
        max_mito = config['params']['predemux']["max-mito"],
        min_umi = config['params']['predemux']["min-umi-count"]
    conda:
        "../envs/predemux.yaml"
    script:
        "../scripts/pdmx_report.py"

rule copy_original_features:
    """
    Copy the original features.tsv.gz file from the filtered Cell Ranger output directory
    to the predemux output directory. This is done to replace the features
    file in the filtered Cell Ranger output with the original one, overcoming
    the loss of Ensembl IDs during Seurat conversion.
    """
    input:
        features = rules.restructure_counts.output.filtered_feat,
        predemux_outs = rules.predemux_filter_seurat.output
    output:
        out_dir/"count/predemux/{capture}/features.tsv.gz"
    log:
        log_dir/"predemux/copy_features/{capture}.log"
    shell:
        "cp -v {input.features} {output}"
