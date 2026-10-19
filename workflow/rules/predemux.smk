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
        filtered_mat = rules.restructure_h5.output.mat
    output:
        rds = temp(out_dir/"predemux/rds/{capture}.rds")
    log:
        log_dir/"predemux/pdmx_convert_seurat/{capture}.log"
    params:
        mito_pattern = config['params']['predemux']["mito-pattern"]
    container:
        config["containers"]["predemux"]
    # conda:  # conda fallback for platforms without singularity
    #     "../envs/predemux.yaml"
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
        barcodes = out_dir/mode/"predemux/{capture}/barcodes.tsv.gz",
        matrix = out_dir/mode/"predemux/{capture}/matrix.mtx.gz",
        filter_metrics = temp(out_dir/"predemux/qc/discarded_metrics/{capture}.csv")
    log:
        log_dir/"predemux/pdmx_filter/{capture}.log"
    params:
        min_genes = config['params']['predemux']["min-gene-count"],
        max_mito = config['params']['predemux']["max-mito"],
        min_umi = config['params']['predemux']["min-umi-count"],
    container:
        config["containers"]["predemux"]
    # conda:  # conda fallback for platforms without singularity
    #     "../envs/predemux.yaml"
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
    container:
        config["containers"]["predemux"]
    # conda:  # conda fallback for platforms without singularity
    #     "../envs/predemux.yaml"
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
        html = report_dir/"cellranger/predemux/predemux_report.html",
        plot_genes = report_dir/"cellranger/predemux/img/plot_genes.png",
        plot_mito = report_dir/"cellranger/predemux/img/plot_mito.png",
        plot_umi = report_dir/"cellranger/predemux/img/plot_umi.png"
    log:
        log_dir/"predemux/predemux_report.log"
    params:
        min_genes = config['params']['predemux']["min-gene-count"],
        max_mito = config['params']['predemux']["max-mito"],
        min_umi = config['params']['predemux']["min-umi-count"]
    container:
        config["containers"]["predemux"]
    # conda:  # conda fallback for platforms without singularity
    #     "../envs/predemux.yaml"
    script:
        "../scripts/pdmx_report.py"

rule copy_original_features:
    """
    Restore the original features.tsv.gz over the one written by predemux_filter_seurat,
    recovering the Ensembl IDs that Seurat conversion drops.

    Keep only the **Gene Expression** rows: predemux filters on the GEX assay, so in multi
    mode the predemux matrix is GEX-only while the original (multimodal) features file also
    lists Antibody Capture rows — restoring it verbatim makes the feature axis longer than
    the matrix, so no 10x reader can open the output (see #124). The original 10x features
    file lists Gene Expression rows first, in the same order as the GEX matrix, so selecting
    them reconciles the two. In count mode every row is already Gene Expression (no-op).
    """
    input:
        features = rules.restructure_counts.output.filtered_feat,
        predemux_outs = rules.predemux_filter_seurat.output
    output:
        out_dir/mode/"predemux/{capture}/features.tsv.gz"
    log:
        log_dir/"predemux/copy_features/{capture}.log"
    shell:
        # NF < 3 keeps any legacy 2-column features file intact; otherwise select GEX rows.
        "zcat {input.features} | awk -F'\\t' 'NF < 3 || $3 == \"Gene Expression\"' | gzip -n > {output} 2> {log}"

rule predemux_sex_calls:
    """
    Per-barcode sex typing (chrY-unique panel + XIST) off the KEPT predemux
    filtered matrix. Emits sex_calls.csv (one row per barcode) with a continuous
    signed `sex_score`, raw chrY/XIST counts, and an explicit
    male|female|ambiguous|low_quality call. Consumed downstream by demux
    (spike-in handling / QC) and mkobj (obs). Because it reads the persistent
    matrix — not the temp() rds — re-tuning thresholds re-runs only this rule.
    Requires features.tsv.gz (via copy_original_features) so gene symbols resolve.
    Sex thresholds are optional config (params.predemux.sex.*); the .get()
    fallbacks below keep it working for configs that omit the block.
    """
    input:
        barcodes = rules.predemux_filter_seurat.output.barcodes,
        matrix = rules.predemux_filter_seurat.output.matrix,
        features = rules.copy_original_features.output,
    output:
        sex_calls = out_dir/mode/"predemux/{capture}/sex_calls.csv"
    log:
        log_dir/"predemux/pdmx_sex/{capture}.log"
    params:
        min_umi = config['params']['predemux'].get('sex', {}).get('min-umi', 200),
        min_genes = config['params']['predemux'].get('sex', {}).get('min-genes', 100),
        chry_min_cp10k = config['params']['predemux'].get('sex', {}).get('chrY-min-cp10k', 1.0),
        xist_min_cp10k = config['params']['predemux'].get('sex', {}).get('xist-min-cp10k', 1.0),
        chry_markers = config['params']['predemux'].get('sex', {}).get('chrY-markers', "RPS4Y1,DDX3Y,UTY,USP9Y,EIF1AY,KDM5D"),
        xist_gene = config['params']['predemux'].get('sex', {}).get('xist-gene', "XIST"),
    container:
        config["containers"]["predemux"]
    # conda:  # conda fallback for platforms without singularity
    #     "../envs/predemux_sex.yaml"
    script:
        "../scripts/pdmx_sex.R"
