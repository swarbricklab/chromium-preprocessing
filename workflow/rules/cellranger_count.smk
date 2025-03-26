rule cellranger_count:
    input:
        fastqs=capturesheet("ge_fastqs"),
        transcriptome=pep.config.resources.transcriptome,
    output:
        out_dir=directory(pep.config.output.cr_outs + "/{capture}"),
        molecule_h5=pep.config.output.cr_outs + "/{capture}/outs/molecule_info.h5",
        bam=pep.config.output.cr_outs + "/{capture}/outs/possorted_genome_bam.bam",
        summary=pep.config.output.cr_outs + "/{capture}/outs/metrics_summary.csv",
    params:
        flags=config["count"]["flags"]
    envmodules:
        "cellranger/9.0.1"
    log:
        "logs/chromium-preprocessing/cellranger_count/{capture}.log"
    shell:
        """
        echo {params.flags}
        chromium_dir={output.out_dir}
        rm -rf $chromium_dir
        PATH=$PWD/profiles/global/nci_a56/resources/:$PATH \
        cellranger count \
            --output-dir $chromium_dir \
            --id={wildcards.capture} \
            --sample={wildcards.capture} \
            --fastqs={input.fastqs} \
            --transcriptome={input.transcriptome} \
            --create-bam=true \
            --jobmode={resources.jobmode} \
            --maxjobs {resources.maxjobs} \
            --jobinterval {resources.jobinterval} \
            --mempercore {resources.mempercore} \
            {params.flags}
        """


rule cr_summarise:
    input:
        individual_summaries=expand(
            pep.config.output.cr_outs + "/{capture}/outs/metrics_summary.csv", 
            capture=captures["capture_id"]
        )
    output:
        group_summary=pep.config.output.cr_outs + "/cr_summary.csv"
    params:
        groups=','.join(captures["capture_id"])
    container:
        "docker://johnyaku/csvkit:1.1.1"
    shell:
        """
            csvstack --group-name capture --groups {params.groups} {input.individual_summaries} \
                > {output.group_summary}
        """
