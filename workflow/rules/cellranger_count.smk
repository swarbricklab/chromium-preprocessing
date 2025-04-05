# This rule file contains rules for running cellranger count
# We prefer count over multi when only gene expression libraries are being processed.

# Extend targets
targets.extend([out_dir/"summary/metrics/cr_summary.csv"])

rule cellranger_count:
    input:
        fastqs=get_fastqs,
        transcriptome=config['ref']['gene-expression']
    output:
        cr_dir=temp(directory(out_dir/"tmp/{capture}"))
    params:
        count_options=get_count_options
    envmodules:
        "cellranger/9.0.1",
        "qsub/ext"
    log:
        "logs/chromium-preprocessing/cellranger_count/{capture}.log"
    shell:
        """
        # Snakemake creates output directory but cellranger complains if directory alrady exists!
        rm -rf {output.cr_dir}

        cellranger count \
            --output-dir {output.cr_dir} \
            --id={wildcards.capture} \
            --sample={wildcards.capture} \
            --fastqs={input.fastqs} \
            --transcriptome={input.transcriptome} \
            --jobmode={resources.jobmode} \
            --maxjobs {resources.maxjobs} \
            --jobinterval {resources.jobinterval} \
            --mempercore {resources.mempercore} \
            {params.count_options} \
            > {log} 2>&1
        rm -rf {output.cr_dir}/SC_RNA_COUNTER_CS
        """

# Restructure summary data
rule restructure_summary:
    input:
        tmp=rules.cellranger_count.output.cr_dir
    output:
        metrics=out_dir/"summary/metrics/{capture}.csv",
        web=out_dir/"summary/web/{capture}.html"
    shell:
        """
        cp -v {input.tmp}/outs//metrics_summary.csv {output.metrics}
        cp -v {input.tmp}/outs//web_summary.html {output.web}
        """

# Restructure bam files
rule restructure_bams:
    input:
        tmp=rules.cellranger_count.output.cr_dir
    output:
        ass_bam=out_dir/"bam/count/{capture}/assigned_alignments.bam",
        ass_bai=out_dir/"bam/count/{capture}/assigned_alignments.bam.bai"
    shell:
        """
        cp -v {input.tmp}/outs/possorted_genome_bam.bam {output.ass_bam}
        cp -v {input.tmp}/outs/possorted_genome_bam.bam.bai {output.ass_bai}
        """

# Restructure and recompress count matrices
rule restructure_counts:
    input:
        tmp=rules.cellranger_count.output.cr_dir
    output:
        filtered_bc=out_dir/"count/filtered_feature_bc_matrix/{capture}/barcodes.tsv.gz",
        filtered_feat=out_dir/"count/filtered_feature_bc_matrix/{capture}/features.tsv.gz",
        filtered_mat=out_dir/"count/filtered_feature_bc_matrix/{capture}/matrix.mtx.gz",
        raw_bc=out_dir/"count/raw_feature_bc_matrix/{capture}/barcodes.tsv.gz",
        raw_feat=out_dir/"count/raw_feature_bc_matrix/{capture}/features.tsv.gz",
        raw_mat=out_dir/"count/raw_feature_bc_matrix/{capture}/matrix.mtx.gz",
    shell:
        """
        zcat {input.tmp}/outs/filtered_feature_bc_matrix/barcodes.tsv.gz | gzip -n > {output.filtered_bc}
        zcat {input.tmp}/outs/filtered_feature_bc_matrix/features.tsv.gz | gzip -n > {output.filtered_feat}
        zcat {input.tmp}/outs/filtered_feature_bc_matrix/matrix.mtx.gz   | gzip -n > {output.filtered_mat}
        zcat {input.tmp}/outs/raw_feature_bc_matrix/barcodes.tsv.gz | gzip -n > {output.raw_bc}
        zcat {input.tmp}/outs/raw_feature_bc_matrix/features.tsv.gz | gzip -n > {output.raw_feat}
        zcat {input.tmp}/outs/raw_feature_bc_matrix/matrix.mtx.gz   | gzip -n > {output.raw_mat}
        """

# Restructure h5 data
rule restructure_h5:
    input:
        tmp=rules.cellranger_count.output.cr_dir
    output:
        mol=out_dir/"h5/{capture}/molecule_info.h5",
        raw=out_dir/"h5/{capture}/raw_feature_bc_matrix.h5",
        filtered=out_dir/"h5/{capture}/filtered_feature_bc_matrix.h5"
    shell:
        """
        cp -v {input.tmp}/outs/molecule_info.h5 {output.mol}
        cp -v {input.tmp}/outs/raw_feature_bc_matrix.h5 {output.raw}
        cp -v {input.tmp}/outs/filtered_feature_bc_matrix.h5 {output.filtered}
        """

