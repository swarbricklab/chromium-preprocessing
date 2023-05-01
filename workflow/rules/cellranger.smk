rule cellranger_count:
    input:
        fastqs=capturesheet("ge_fastqs")
    output:
        out_dir=directory(pep.config.cr_outs + "/{capture}"),
        summary=pep.config.cr_outs + "/{capture}/outs/metrics_summary.csv"
    resources:
        cores="16",
        mem=round(int({resources.cores}) * 8 * 0.9)
        tmp_requested="80G",
        tmpfree="80G"
    params:
        transcriptome=pep.config.transcriptome,
        flags=config['count_flags']
    container:
        config["container"]
    log:
        "logs/cr_count/{capture}.log"
    script:
        "../scripts/cellwrapper_count.sh"

rule cr_summarise:
    input:
        individual_summaries=expand(
            pep.config.cr_outs + "/{capture}/outs/metrics_summary.csv", 
            capture=captures["capture_id"]
        )
    output:
        group_summary=pep.config.cr_outs + "/cr_summary.csv"
    params:
        groups=','.join(captures["capture_id"])
    container:
        "docker://johnyaku/csvkit:1.1.1"
    shell:
        """
            csvstack --group-name capture --groups {params.groups} {input.individual_summaries} \
                > {output.group_summary}
        """
