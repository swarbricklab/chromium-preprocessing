# rule to generate input csv config files for aggr
# use a 'pool' column in config sample-sheet
rule generate_aggr_csv:
    input:
        captures=config["deps"]["captures"]
    output:
        csv=temp(out_dir/"aggr/csv/{pool}.csv")
    log:
        "logs/chromium-preprocessing/generate_aggr_csvs/{pool}.log"
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

# rule to run cellranger aggr on defined aggr_id groups
rule cellranger_aggr:
    input:
        csv=rules.generate_aggr_csv.output.csv,
        molecule_h5=get_h5_in_pool
    output:
        aggr_dir=directory(out_dir/"aggr/{pool}"),
        summary=out_dir/"aggr/{pool}/outs/count/summary.json"
    params:
        aggr_options=get_options("aggr")
    envmodules:
        "cellranger/9.0.1",
        "qsub/ext"
    log:
        "logs/chromium-preprocessing/cellranger_aggr/{pool}.log"
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
        bam=out_dir/"bams/{pool}/merged.bam"
    container:
        "docker://quay.io/biocontainers/samtools:0.1.19--h270b39a_9"
    log:
        "logs/chromium-preprocessing/merge_bams/{pool}.log"
    script:
        "workflow/scripts/merge_bams.sh"

rule index_merged_bam:
    input:
        bam=rules.merge_bams.output.bam
    output:
        bai=out_dir/"bams/{pool}/merged.bam.bai"
    container:
        "docker://quay.io/biocontainers/samtools:0.1.19--h270b39a_9"
    log:
        "logs/chromium-preprocessing/index_merged_bam/{pool}.log"
    shell:
        """
        samtools index {input.bam}
        """
