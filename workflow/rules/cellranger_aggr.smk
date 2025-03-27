# rule to generate input csv config files for aggr
# use an aggr_id column in config sample-sheet
rule generate_aggr_csv:
    input:
        sample_sheet=config["aggr"]["samples"]
    output:
        aggr_csv=temp(aggr_dir/"csvs/{aggr_id}.csv")
    params:
        cr_outs=count_dir
    conda:
        "../envs/generate_aggr_csv.yaml"
    log:
        "logs/chromium-preprocessing/generate_aggr_csvs/{aggr_id}.generate_aggr_csv.log"
    script:
        "../scripts/generate_aggr_csv.py"

# rule to run cellranger aggr on defined aggr_id groups
rule cellranger_aggr:
    input:
        aggr_csv=rules.generate_aggr_csv.output.aggr_csv,
        molecule_h5=get_cellranger_aggr_aggr_captures_input
    output:
        out_dir=directory(aggr_dir/"output/{aggr_id}"),
        summary=aggr_dir/"output/{aggr_id}/outs/count/summary.json"
    params:
        flags=config["aggr"]["flags"]
    envmodules:
        "cellranger/9.0.1"
    log:
        "logs/chromium-preprocessing/cellranger_aggr/{aggr_id}.cellranger_aggr.log"
    shell:
        """
        # Snakemake creates output directory but cellranger complains if directory alrady exists!
        rm -rf {output.out_dir}
        PATH=$PWD/profiles/global/nci_a56/resources/:$PATH \
        cellranger aggr \
            --output-dir {output.out_dir} \
            --id={wildcards.aggr_id} \
            --csv={input.aggr_csv} \
            --normalize=mapped \
            --jobmode={resources.jobmode} \
            --maxjobs {resources.maxjobs} \
            --jobinterval {resources.jobinterval} \
            --mempercore {resources.mempercore} \
            {params.flags} \
            > {log} 2>&1
        """

# Rule to merge bam files for captures defined by 'aggr_id'
# '-1' suffixes are replaced by '-2', '-3' etc to match the order in the count magrix produced by cellranger aggr
rule merge_bams:
    input:
        source_bams=get_source_bams,
        aggr_summary=rules.cellranger_aggr.output.summary
    output:
        out_bam=aggr_dir/"bams/{aggr_id}/merged.bam"
    params:
        sample_sheet=config["aggr"]["samples"]
    container:
        "docker://quay.io/biocontainers/samtools:0.1.19--h270b39a_9"
    log:
        "logs/chromium-preprocessing/merge_bams/{aggr_id}.log"
    script:
        "../scripts/merge_bams.sh"
