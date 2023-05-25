rule cellranger_count:
    input:
        fastqs=capturesheet("ge_fastqs")
    output:
        out_dir=directory(pep.config.output.cr_outs + "/{capture}"),
        summary=pep.config.output.cr_outs + "/{capture}/outs/metrics_summary.csv"
    resources:
        cores="16",
        mem="110GB",
        tmp_requested="80G",
        tmpfree="80G"
    params:
        transcriptome=pep.config.resources.transcriptome,
        flags=config['count_flags']
    container:
        config["cr_container_publisher"] + config["cr_version"]
    log:
        "logs/cr_count/{capture}.log"
    script:
        "../scripts/cellwrapper_count.sh"

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
