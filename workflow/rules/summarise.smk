# This rule file includes for reorganising and summarising the output from multi or count

rule cr_summarise:
    input:
        individual_summaries=expand(
            out_dir/"summary/metrics/{capture}.csv", 
            capture=captures.index
        )
    output:
        group_summary=out_dir/"summary/metrics/cr_summary.csv"
    params:
        groups=','.join(captures.index)
    container:
        "docker://johnyaku/csvkit:1.1.1"
    shell:
        """
            csvstack --group-name capture --groups {params.groups} {input.individual_summaries} \
                > {output.group_summary}
        """