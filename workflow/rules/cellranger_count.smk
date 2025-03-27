rule cellranger_count:
    input:
        fastqs=capturesheet("ge_fastqs"),
        transcriptome=config['deps']['transcriptome']
    output:
        out_dir=directory(count_dir/"{capture}"),
        molecule_h5=count_dir/"{capture}/outs/molecule_info.h5",
        bam=count_dir/"{capture}/outs/possorted_genome_bam.bam",
        summary=count_dir/"{capture}/outs/metrics_summary.csv"
    params:
        flags=config["params"]["count"]["flags"]
    envmodules:
        "cellranger/9.0.1"
    log:
        "logs/chromium-preprocessing/cellranger_count/{capture}.log"
    shell:
        """
        # Snakemake creates output directory but cellranger complains if directory alrady exists!
        rm -rf {output.out_dir}
        PATH=$PWD/profiles/global/nci_a56/resources/:$PATH \
        cellranger count \
            --output-dir {output.out_dir} \
            --id={wildcards.capture} \
            --sample={wildcards.capture} \
            --fastqs={input.fastqs} \
            --transcriptome={input.transcriptome} \
            --create-bam=true \
            --jobmode={resources.jobmode} \
            --maxjobs {resources.maxjobs} \
            --jobinterval {resources.jobinterval} \
            --mempercore {resources.mempercore} \
            {params.flags} \
            > {log} 2>&1
        rm -rf {output.out_dir}/SC_RNA_COUNTER_CS
        """


rule cr_summarise:
    input:
        individual_summaries=expand(
            count_dir/"{capture}/outs/metrics_summary.csv", 
            capture=captures.index
        )
    output:
        group_summary=count_dir/"cr_summary.csv"
    params:
        groups=','.join(captures.index)
    container:
        "docker://johnyaku/csvkit:1.1.1"
    shell:
        """
            csvstack --group-name capture --groups {params.groups} {input.individual_summaries} \
                > {output.group_summary}
        """
