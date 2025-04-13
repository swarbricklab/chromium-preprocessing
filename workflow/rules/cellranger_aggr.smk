# rule to generate input csv config files for aggregating gene expression and feature barcode count matrices
# Use a 'pool' column in config sample-sheet
rule generate_aggr_count_csv:
    input:
        captures=config["deps"]["captures"]
    output:
        csv=temp(out_dir/"aggr_tmp/count/csv/{pool}.csv")
    log:
        "logs/chromium-preprocessing/generate_aggr_csvs/count/{pool}.log"
    run:
        import pandas as pd
        capture_list = captures[captures['pool'] == wildcards.pool].index.tolist()
        h5_list = expand(out_dir/"h5/{capture}/molecule_info.h5",capture=capture_list)
        df = pd.DataFrame(
            {
                'sample_id': capture_list,
                'molecule_h5': h5_list
            }
        )
        df.to_csv(output.csv, index=False)

# rule to run cellranger aggr for count matrices on defined pool groups
rule cellranger_aggr_count:
    input:
        csv=rules.generate_aggr_count_csv.output.csv,
        molecule_h5=get_h5_in_pool
    output:
        aggr_dir=temp(directory(out_dir/"aggr_tmp/count/{pool}"))
    params:
        aggr_options=get_options("aggr")
    envmodules:
        "cellranger/9.0.1",
        "qsub/ext"
    log:
        "logs/chromium-preprocessing/cellranger_aggr/count/{pool}.log"
    shell:
        """
        # Snakemake creates output directory but cellranger complains if directory alrady exists!
        # rm -rf {output.aggr_dir}
        cellranger aggr \
            --output-dir {output.aggr_dir} \
            --id={wildcards.pool} \
            --csv={input.csv} \
            --jobmode={resources.jobmode} \
            --maxjobs {resources.maxjobs} \
            --jobinterval {resources.jobinterval} \
            --mempercore {resources.mempercore} \
            {params.aggr_options} \
            > {log} 2>&1
        rm -rf {output.aggr_dir}/SC_RNA_AGGREGATOR_CS
        """

# rule to generate input csv config files for aggregating gene expression and feature barcode count matrices
# Use a 'pool' column in config sample-sheet
rule generate_aggr_vdj_csv:
    input:
        captures=config["deps"]["captures"]
    output:
        csv=temp(out_dir/"aggr_tmp/{vdj_assay}/csv/{pool}.csv")
    log:
        "logs/chromium-preprocessing/generate_aggr_csvs/{vdj_assay}/{pool}.log"
    run:
        import pandas as pd
        capture_list = captures[captures['pool'] == wildcards.pool].index.tolist()
        n_captures = len(capture_list)
        pb_list = expand(out_dir/"{vdj_assay}/results/{capture}/vdj_contig_info.pb",capture=capture_list, vdj_assay=wildcards.vdj_assay)
        df = pd.DataFrame(
            {
                'sample_id': capture_list,
                'vdj_contig_info': pb_list,
                'donor': [wildcards.pool] * n_captures,
                'origin': capture_list
            }
        )
        df.to_csv(output.csv, index=False)

# rule to run cellranger aggr for count matrices on defined pool groups
rule cellranger_aggr_vdj:
    input:
        csv=rules.generate_aggr_vdj_csv.output.csv,
        molecule_h5=get_pb_in_pool
    output:
        aggr_dir=directory(out_dir/"aggr_tmp/vdj/{vdj_assay}/{pool}")
    params:
        aggr_options=get_options("aggr")
    envmodules:
        "cellranger/9.0.1",
        "qsub/ext"
    log:
        "logs/chromium-preprocessing/cellranger_aggr/{vdj_assay}/{pool}.log"
    shell:
        """
        # Snakemake creates output directory but cellranger complains if directory alrady exists!
        rm -rf {output.aggr_dir}
        cellranger aggr \
            --output-dir {output.aggr_dir} \
            --id={wildcards.pool} \
            --csv={input.csv} \
            --jobmode={resources.jobmode} \
            --maxjobs {resources.maxjobs} \
            --jobinterval {resources.jobinterval} \
            --mempercore {resources.mempercore} \
            {params.aggr_options} \
            > {log} 2>&1
        rm -rf {output.aggr_dir}/SC_RNA_AGGREGATOR_CS
        """

# Rule to merge bam files for captures defined by 'aggr_id'
# '-1' suffixes are replaced by '-2', '-3' etc to match the order in the count magrix produced by cellranger aggr
rule merge_bams:
    input:
        source_bams=get_source_bams
    output:
        bam=out_dir/"bam/count/pools/{pool}/merged.bam"
    container:
        "docker://quay.io/biocontainers/samtools:0.1.19--h270b39a_9"
    log:
        "logs/chromium-preprocessing/merge_bams/{pool}.log"
    script:
        "../scripts/merge_bams.sh"

rule index_merged_bam:
    input:
        bam=rules.merge_bams.output.bam
    output:
        bai=out_dir/"bam/{pool}/merged.bam.bai"
    container:
        "docker://quay.io/biocontainers/samtools:0.1.19--h270b39a_9"
    log:
        "logs/chromium-preprocessing/index_merged_bam/{pool}.log"
    shell:
        """
        samtools index {input.bam}
        """

rule restructure_aggr_counts:
    input:
        counts=rules.cellranger_aggr_count.output.aggr_dir
    output:
        bc=out_dir/"count/aggr/{pool}/barcodes.tsv.gz",
        feat=out_dir/"count/aggr/{pool}/features.tsv.gz",
        mat=out_dir/"count/aggr/{pool}/matrix.mtx.gz"
    shell:
        """
        counts={input.counts}/outs/count/filtered_feature_bc_matrix
        cp -v $counts/barcodes.tsv.gz {output.bc}
        cp -v $counts/features.tsv.gz {output.feat}
        cp -v $counts/matrix.mtx.gz {output.mat}
        """

rule restructure_aggr_summary:
    input:
        counts=rules.cellranger_aggr_count.output.aggr_dir
    output:
        web=out_dir/"summary/web/pools/{pool}.html",
        loupe=out_dir/"loupe/count/aggr/{pool}.cloupe",
        h5=out_dir/"h5/pools/{pool}/filtered_feature_bc_matrix.h5"
    shell:
        """
        out={input.counts}/out
        cp -v $out/web_summary.html {output.web}
        cp -v $out/count/cloupe.cloupe {output.loupe}
        cp -v $out/count/filtered_feature_bc_matrix.h5 {output.h5}
        """

rule restructure_aggr_analysis:
    input:
        counts=rules.cellranger_aggr_count.output.aggr_dir
    output:
        dir=directory(out_dir/"cr_analysis/pools/{pool}")
    shell:
        """
        counts={input.counts}/outs/count
        cp -r -v $counts/analysis {output.dir}
        """
