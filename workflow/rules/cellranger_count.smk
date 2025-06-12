# This rule file contains rules for running cellranger count
# We prefer count over multi when only gene expression libraries are being processed.

rule cellranger_count:
    input:
        fastqs=get_fastqs,
        transcriptome=config['ref']['gene-expression']
    output:
        cr_dir=temp(directory(out_dir/"tmp/{capture}"))
    params:
        count_options=get_options('gene-expression')
    envmodules:
        f"cellranger/{config['modules']['cellranger']}",
        "qsub/ext"
    log:
        "logs/chromium-preprocessing/cellranger_count/{capture}.log"
    shell:
        """
        # Snakemake creates output directory but cellranger complains if directory alrady exists!
        [ -d {output.cr_dir} ] && [ -z "$(ls -A {output.cr_dir})" ] && rm -rf {output.cr_dir}

        cellranger count \
            --output-dir {output.cr_dir} \
            --id={wildcards.capture} \
            --sample={wildcards.capture} \
            --fastqs=$(echo {input.fastqs} | tr ' ' ',') \
            --transcriptome={input.transcriptome} \
            --jobmode {resources.jobmode} \
            --overrides {resources.override} \
            --maxjobs {resources.maxjobs} \
            --jobinterval {resources.jobinterval} \
            --mempercore {resources.mempercore} \
            {params.count_options} \
            > {log} 2>&1
        rm -rf {output.cr_dir}/SC_RNA_COUNTER_CS
        """
        
